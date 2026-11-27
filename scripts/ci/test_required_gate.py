import unittest

from required_gate import ALWAYS, SELF, evaluate

_id = [0]


def run(name, status="completed", conclusion="success", slug="github-actions"):
    _id[0] += 1
    return {"id": _id[0], "name": name, "status": status, "conclusion": conclusion, "app": {"slug": slug}}


def base(**over):
    runs = {n: run(n) for n in ALWAYS}
    runs.update(over)
    return list(runs.values())


class RequiredGateTest(unittest.TestCase):
    def test_all_green_passes(self):
        self.assertEqual(evaluate(base(backend=run("backend")), 120)[0], "pass")

    def test_skipped_and_neutral_are_fine(self):
        self.assertEqual(evaluate(base(a=run("sdk-tooling", conclusion="skipped"), b=run("x", conclusion="neutral")), 120)[0], "pass")

    def test_failure_cancelled_timed_out_block(self):
        for conclusion in ("failure", "cancelled", "timed_out", "action_required", "stale", "startup_failure"):
            self.assertEqual(evaluate(base(b=run("backend", conclusion=conclusion)), 120)[0], "fail", conclusion)

    def test_failure_blocks_immediately_even_while_others_run(self):
        runs = base(b=run("backend", conclusion="failure"), f=run("flutter", status="in_progress", conclusion=None))
        self.assertEqual(evaluate(runs, 5)[0], "fail")

    def test_pending_check_waits(self):
        self.assertEqual(evaluate(base(b=run("backend", status="in_progress", conclusion=None)), 120)[0], "wait")
        self.assertEqual(evaluate(base(b=run("backend", status="queued", conclusion=None)), 120)[0], "wait")

    def test_missing_always_check_waits_then_fails(self):
        runs = [r for r in base() if r["name"] != "secrets"]
        self.assertEqual(evaluate(runs, 120)[0], "wait")
        verdict, lines = evaluate(runs, 2400)
        self.assertEqual(verdict, "fail")
        self.assertIn("secrets", lines[-1])

    def test_settle_period_before_first_pass(self):
        self.assertEqual(evaluate(base(), 10)[0], "wait")

    def test_rerun_replaces_older_result(self):
        old = run("backend", conclusion="failure")
        new = run("backend", conclusion="success")
        self.assertEqual(evaluate(base() + [old, new], 120)[0], "pass")  # later id wins: re-run fixed it
        self.assertEqual(evaluate(base() + [new, run("backend", conclusion="failure")], 120)[0], "fail")  # later failure wins

    def test_ignores_itself_and_foreign_checks(self):
        runs = base(s=run(SELF, status="in_progress", conclusion=None), c=run("CodeRabbit", conclusion="failure", slug="coderabbitai"))
        self.assertEqual(evaluate(runs, 120)[0], "pass")

    def test_no_checks_at_all_never_passes(self):
        self.assertEqual(evaluate([], 120)[0], "wait")
        self.assertEqual(evaluate([], 2400)[0], "fail")


if __name__ == "__main__":
    unittest.main()
