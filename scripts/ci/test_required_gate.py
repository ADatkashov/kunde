import unittest

import detect_affected as da
import required_gate as g

D = da.Detector()
_id = [0]


def run(path, status="completed", conclusion="success"):
    _id[0] += 1
    return {"id": _id[0], "path": ".github/workflows/" + path, "status": status, "conclusion": conclusion}


def job(name, conclusion="success", status="completed", steps=()):
    return {"name": name, "status": status, "conclusion": conclusion,
            "steps": [{"name": n, "conclusion": c} for n, c in steps]}


EXPECTED = {
    ".github/workflows/ci.yml": {"jobs": {"configuration": False}},
    ".github/workflows/security.yml": {"jobs": {"secrets": False, "sdk-tooling": True}},
    ".github/workflows/backend.yml": {"jobs": {"backend": False, "docker-image": False}},
}
BACKEND_OK = [(s, "success") for s in g.BACKEND_STEPS]


def scenario(**over):
    """runs + jobs for a fully green PR; keyword overrides replace one workflow's jobs."""
    runs = {p.rsplit("/", 1)[1]: run(p.rsplit("/", 1)[1]) for p in EXPECTED}
    jobs = {
        "ci.yml": [job("configuration")],
        "security.yml": [job("secrets"), job("sdk-tooling", "skipped")],
        "backend.yml": [job("backend", steps=BACKEND_OK), job("docker-image")],
    }
    for k, v in over.items():
        key = k.replace("_yml", ".yml")
        if isinstance(v, dict):
            runs[key] = v
        else:
            jobs[key] = v
    return list(runs.values()), {runs[k]["id"]: v for k, v in jobs.items()}


def verdict(over=None, steps=None, elapsed=120, timeout=2400, expected=EXPECTED, **kw):
    runs, jobs = scenario(**(over or {}), **kw)
    return g.evaluate(expected, runs, jobs, steps if steps is not None else {"backend": g.BACKEND_STEPS}, elapsed, timeout)


class GateEvaluation(unittest.TestCase):
    def test_green_passes(self):
        self.assertEqual(verdict()[0], "pass")

    def test_job_without_if_must_not_be_skipped(self):
        v, lines = verdict(backend_yml=[job("backend", "skipped"), job("docker-image")])
        self.assertEqual(v, "fail")
        self.assertTrue(any("but the change requires it" in l for l in lines))

    def test_job_with_if_may_be_skipped(self):
        self.assertEqual(verdict()[0], "pass")  # sdk-tooling is skipped in the green scenario

    def test_missing_job_fails(self):
        self.assertEqual(verdict(backend_yml=[job("backend", steps=BACKEND_OK)])[0], "fail")

    def test_pending_is_never_success(self):
        v, _ = verdict(backend_yml=[job("backend", None, "in_progress"), job("docker-image")])
        self.assertEqual(v, "wait")
        v, lines = verdict(backend_yml=[job("backend", None, "queued"), job("docker-image")], elapsed=2400)
        self.assertEqual(v, "fail")
        self.assertIn("timed out", lines[-1])

    def test_failure_blocks_even_while_others_run(self):
        runs = [run("ci.yml", conclusion="failure"), run("security.yml", "in_progress", None), run("backend.yml", "in_progress", None)]
        self.assertEqual(g.evaluate(EXPECTED, runs, {}, {}, 5, 2400)[0], "fail")

    def test_every_bad_conclusion_fails(self):
        for c in ("failure", "cancelled", "timed_out", "action_required", "stale", "startup_failure"):
            self.assertEqual(verdict(ci_yml=run("ci.yml", conclusion=c))[0], "fail", c)
            self.assertEqual(verdict(backend_yml=[job("backend", c, steps=BACKEND_OK), job("docker-image")])[0], "fail", c)

    def test_missing_run_waits_then_fails(self):
        runs, jobs = scenario()
        runs = [r for r in runs if not r["path"].endswith("backend.yml")]
        self.assertEqual(g.evaluate(EXPECTED, runs, jobs, {}, 120, 2400)[0], "wait")
        v, lines = g.evaluate(EXPECTED, runs, jobs, {}, 2400, 2400)
        self.assertEqual(v, "fail")
        self.assertIn("backend.yml (no run yet)", lines[-1])

    def test_required_step_skipped_by_detector_decision_fails(self):
        steps = [(s, "skipped" if s == "Verify and package" else "success") for s in g.BACKEND_STEPS]
        v, lines = verdict(backend_yml=[job("backend", steps=steps), job("docker-image")])
        self.assertEqual(v, "fail")
        self.assertTrue(any("Verify and package" in l for l in lines))

    def test_required_step_missing_fails(self):
        self.assertEqual(verdict(backend_yml=[job("backend", steps=[(g.DETECT_STEP, "success")]), job("docker-image")])[0], "fail")

    def test_steps_not_required_when_detector_says_skip(self):
        steps = [(g.DETECT_STEP, "success")] + [(s, "skipped") for s in g.BACKEND_STEPS[1:]]
        v, _ = verdict(steps={"backend": [g.DETECT_STEP]}, backend_yml=[job("backend", steps=steps), job("docker-image")])
        self.assertEqual(v, "pass")

    def test_unexpected_red_run_fails_and_unexpected_green_is_ignored(self):
        runs, jobs = scenario()
        extra = run("terraform-dev.yml", conclusion="failure")
        self.assertEqual(g.evaluate(EXPECTED, runs + [extra], jobs, {}, 120, 2400)[0], "fail")
        self.assertEqual(g.evaluate(EXPECTED, runs + [run("terraform-dev.yml")], jobs, {}, 120, 2400)[0], "pass")

    def test_gate_never_waits_for_itself(self):
        runs, jobs = scenario()
        self.assertEqual(g.evaluate(EXPECTED, runs + [run("ci-pr.yml", "in_progress", None)], jobs, {}, 120, 2400)[0], "pass")

    def test_rerun_latest_run_wins(self):
        old = run("backend.yml", conclusion="failure")
        runs, jobs = scenario()
        self.assertEqual(g.evaluate(EXPECTED, [old] + runs, jobs, {}, 120, 2400)[0], "pass")
        newer_bad = run("backend.yml", conclusion="failure")
        self.assertEqual(g.evaluate(EXPECTED, runs + [newer_bad], jobs, {}, 120, 2400)[0], "fail")

    def test_settle_period_and_empty_gate(self):
        self.assertEqual(verdict(elapsed=10)[0], "wait")
        self.assertEqual(g.evaluate({}, [], {}, {}, 120, 2400)[0], "fail")


class PathFilters(unittest.TestCase):
    def test_glob_rules(self):
        t = g.triggered
        self.assertTrue(t(["backend/**"], ["backend/services/a/b.java"]))
        self.assertFalse(t(["backend/**"], ["apps/consumer/a.dart"]))
        self.assertFalse(t(["*.md"], ["docs/a.md"]))
        self.assertTrue(t(["*.md"], ["a.md"]))
        self.assertTrue(t(None, ["anything"]))
        self.assertTrue(t(["!docs/**", "backend/**"], ["x"]))  # negation is not modelled: fail closed

    def test_real_workflows_expectations(self):
        wf = g.load_workflows()
        home = [p for p, w in wf.items() if g.triggered(w["paths"], ["backend/services/homeservices/A.java"])]
        self.assertEqual(sorted(home), [".github/workflows/backend.yml", ".github/workflows/ci.yml", ".github/workflows/security.yml"])
        docs = [p for p, w in wf.items() if g.triggered(w["paths"], ["docs/a.md"])]
        self.assertEqual(sorted(docs), [".github/workflows/ci.yml", ".github/workflows/security.yml"])
        self.assertNotIn(g.SELF_WORKFLOW, wf)
        self.assertTrue(wf[".github/workflows/security.yml"]["jobs"]["sdk-tooling"])  # has an `if`
        self.assertFalse(wf[".github/workflows/backend.yml"]["jobs"]["backend"])

    def test_required_step_names_exist_in_the_real_workflows(self):
        wf = g.load_workflows()
        for step in g.BACKEND_STEPS:
            self.assertIn(step, wf[".github/workflows/backend.yml"]["steps"]["backend"])
        for job_name, (file, _app) in g.FLUTTER_JOBS.items():
            for step in g.FLUTTER_STEPS:
                self.assertIn(step, wf[".github/workflows/" + file]["steps"][job_name], file)


class DetectorDrivenRequirements(unittest.TestCase):
    def need(self, files, expected):
        return g.required_steps(D.detect(files), {p: {} for p in expected})

    def test_backend_change_requires_all_backend_steps(self):
        need = self.need(["backend/services/homeservices/A.java"], [".github/workflows/backend.yml"])
        self.assertEqual(need["backend"], g.BACKEND_STEPS)

    def test_docs_only_backend_touch_requires_only_detection(self):
        need = self.need(["backend/README.md"], [".github/workflows/backend.yml"])
        self.assertEqual(need["backend"], [g.DETECT_STEP])

    def test_unreachable_flutter_app_requires_only_detection(self):
        need = self.need(["packages/kunde_maps/lib/a.dart"], [".github/workflows/admin-flutter.yml", ".github/workflows/flutter.yml"])
        self.assertEqual(need["admin-flutter"], [g.DETECT_STEP])
        self.assertEqual(need["flutter"], g.FLUTTER_STEPS)

    def test_full_scope_requires_everything(self):
        need = self.need(["scripts/ci/x.py"], [".github/workflows/backend.yml", ".github/workflows/executor-flutter.yml"])
        self.assertEqual(need["backend"], g.BACKEND_STEPS)
        self.assertEqual(need["executor-flutter"], g.FLUTTER_STEPS)


if __name__ == "__main__":
    unittest.main()
