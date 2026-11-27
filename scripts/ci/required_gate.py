#!/usr/bin/env python3
"""Required CI Gate (ADR-027): one always-running check that proves the PR's other checks did what the change requires.

A `skipped` job is not automatically fine. The gate computes what MUST have run from two independent sources:
  1. workflow definitions: every workflow with a `pull_request` trigger whose `paths:` filter matches the PR's changed files
     (or that has no filter) must have a completed, successful run on the PR head commit; each of its jobs must be present and
     successful, and may be skipped only if the job itself declares an `if:` (e.g. sdk-tooling);
  2. detect_affected.py on the same changed files: when the detector says backend/Flutter tests are required, the job's steps
     (Detect affected modules, Verify and package, Test ...) must have concluded `success`, not `skipped`.
Anything else fails closed: missing run/job/step, pending past the timeout, failure/cancelled/timed_out/action_required, stale head SHA
(the PR moved on), API errors. Pending is never success. The gate's own workflow (ci-pr.yml) is excluded, so it never waits for itself.
Races: expectations come from files and YAML, not from what happens to be registered yet; a missing run is "wait" until the timeout.
Usage: required_gate.py <owner/repo> <pr_number> <head_sha> [timeout_seconds]; GH_TOKEN needs checks/actions/pull-requests read.
"""
import json
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
SELF_WORKFLOW = ".github/workflows/ci-pr.yml"
GOOD_RUN = {"success"}
BAD = {"failure", "cancelled", "timed_out", "action_required", "stale", "startup_failure"}
SETTLE_SECONDS = 45  # let sibling workflows register their runs before the first "pass"
DETECT_STEP = "Detect affected modules"
BACKEND_STEPS = [DETECT_STEP, "Architecture boundaries (fast, no database)", "Verify and package",
                 "Packaged JAR HTTP and fail-closed smoke"]
FLUTTER_STEPS = [DETECT_STEP, "Resolve, analyze and check format", "Test (whole suite or affected features only)"]
FLUTTER_JOBS = {"flutter": ("flutter.yml", "consumer"), "executor-flutter": ("executor-flutter.yml", "executor"),
                "admin-flutter": ("admin-flutter.yml", "admin")}


def glob_to_regex(pattern):
    """GitHub path filter glob: `**` crosses directories, `*` and `?` do not."""
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**", i):
            out += ".*"
            i += 2
        elif pattern[i] == "*":
            out += "[^/]*"
            i += 1
        elif pattern[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(pattern[i])
            i += 1
    return re.compile(out + r"\Z")


def triggered(paths_filter, changed):
    if not paths_filter:
        return True
    if any(p.startswith("!") for p in paths_filter):
        return True  # negated patterns are not modelled: expect the workflow (fail closed)
    regexes = [glob_to_regex(p) for p in paths_filter]
    return any(r.match(c) for r in regexes for c in changed)


def load_workflows(directory=ROOT / ".github/workflows"):
    """relpath -> {"paths": [...] | None, "jobs": {display name: has_if}} for every workflow triggered by pull_request."""
    import yaml
    result = {}
    for path in sorted(pathlib.Path(directory).glob("*.yml")):
        rel = ".github/workflows/" + path.name
        data = yaml.load(path.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
        on = data.get("on")
        if isinstance(on, list):
            on = {k: None for k in on}
        if not isinstance(on, dict) or "pull_request" not in on or rel == SELF_WORKFLOW:
            continue
        pr = on["pull_request"] or {}
        result[rel] = {"paths": pr.get("paths") if isinstance(pr, dict) else None,
                       "jobs": {j.get("name", key): "if" in j for key, j in data["jobs"].items()},
                       "steps": {j.get("name", key): [s.get("name") for s in j.get("steps", [])] for key, j in data["jobs"].items()}}
    return result


def required_steps(detection, expected):
    """job display name -> steps that must be `success` according to the detector result."""
    from backend_gradle_args import gradle_args
    from flutter_selection import selection
    need = {}
    if ".github/workflows/backend.yml" in expected:
        need["backend"] = [DETECT_STEP] if gradle_args(detection)[0] == "skip" else list(BACKEND_STEPS)
    for job, (wf, app) in FLUTTER_JOBS.items():
        if ".github/workflows/" + wf in expected:
            need[job] = [DETECT_STEP] if selection(detection, app)["mode"] == "skip" else list(FLUTTER_STEPS)
    return need


def evaluate(expected, runs, jobs_by_run, step_requirements, elapsed=0, timeout=2400):
    """-> (verdict, lines); verdict 'pass' | 'fail' | 'wait'. Pure function: all inputs are plain data."""
    latest = {}
    for run in runs:
        if run["path"] == SELF_WORKFLOW:
            continue
        if run["path"] not in latest or run["id"] > latest[run["path"]]["id"]:
            latest[run["path"]] = run
    lines, bad, pending = [], [], []

    def fail(msg):
        bad.append(msg)
        lines.append("FAIL  " + msg)

    for path, run in sorted(latest.items()):
        if path not in expected:  # triggered although no filter matched: still must not be red or running
            if run["status"] != "completed":
                pending.append(path)
            elif run["conclusion"] in BAD:
                fail("%s (not expected by its path filter) concluded %s" % (path, run["conclusion"]))
    for path, spec in sorted(expected.items()):
        run = latest.get(path)
        if run is None:
            pending.append(path + " (no run yet)")
            continue
        if run["status"] != "completed":
            pending.append(path)
            continue
        if run["conclusion"] not in GOOD_RUN:
            fail("%s concluded %s" % (path, run["conclusion"]))
            continue
        jobs = {j["name"]: j for j in jobs_by_run.get(run["id"], [])}
        for name, has_if in sorted(spec["jobs"].items()):
            job = jobs.get(name)
            if job is None:
                fail("%s: job %r missing" % (path, name))
            elif job["status"] != "completed":
                pending.append("%s: %s" % (path, name))
            elif job["conclusion"] == "success":
                steps = {s["name"]: s for s in job.get("steps", [])}
                for step in step_requirements.get(name, []):
                    s = steps.get(step)
                    if s is None or s["conclusion"] != "success":
                        fail("%s: required step %r of job %r is %s" % (path, step, name, s["conclusion"] if s else "missing"))
            elif job["conclusion"] == "skipped" and has_if:
                lines.append("ok    %s: %s skipped (job has an `if`)" % (path, name))
            else:
                fail("%s: job %r %s%s" % (path, name, job["conclusion"], " but the change requires it" if job["conclusion"] == "skipped" else ""))
        if not any(l.startswith("FAIL") and path in l for l in lines):
            lines.append("ok    " + path)
    if bad:
        return "fail", lines
    if pending:
        if elapsed >= timeout:
            lines.append("FAIL  timed out after %ds waiting for: %s" % (elapsed, "; ".join(pending)))
            return "fail", lines
        lines.append("wait  " + "; ".join(pending))
        return "wait", lines
    if elapsed < SETTLE_SECONDS:
        return "wait", lines + ["wait  settle period"]
    if not expected:
        return "fail", lines + ["FAIL  no workflow is expected to run: refusing to pass an empty gate"]
    return "pass", lines


def gh(path):
    return json.loads(subprocess.check_output(["gh", "api", path], text=True))


def changed_files(repo, number):
    files, page = [], 1
    while True:
        batch = gh("repos/%s/pulls/%s/files?per_page=100&page=%d" % (repo, number, page))
        for f in batch:
            files += [f["filename"]] + ([f["previous_filename"]] if f.get("previous_filename") else [])
        if len(batch) < 100:
            return files, page >= 30  # the API caps at 3000 files: then everything is "expected"
        page += 1


def main(argv):
    repo, number, head = argv[1], argv[2], argv[3]
    timeout = int(argv[4]) if len(argv) > 4 else 2400
    workflows = load_workflows()
    start = time.monotonic()
    files, truncated = changed_files(repo, number)
    expected = {p: w for p, w in workflows.items() if truncated or triggered(w["paths"], files)}
    import detect_affected
    try:
        detection = detect_affected.Detector().detect(files)
    except Exception as exc:  # fail closed: a broken detector means everything was required
        detection = detect_affected.full_fallback("detector failed in gate: %s" % exc)
    steps = required_steps(detection, expected)
    while True:
        elapsed = int(time.monotonic() - start)
        pr = gh("repos/%s/pulls/%s" % (repo, number))
        if pr["head"]["sha"] != head:
            print("FAIL  head moved to %s: this gate run is stale" % pr["head"]["sha"])
            return 1
        runs = [r for r in gh("repos/%s/actions/runs?head_sha=%s&per_page=100" % (repo, head))["workflow_runs"] if r["event"] == "pull_request"]
        wanted = {r["id"] for r in runs if r["path"] in expected}
        jobs = {rid: gh("repos/%s/actions/runs/%d/jobs?filter=latest&per_page=100" % (repo, rid))["jobs"] for rid in wanted}
        verdict, lines = evaluate({p: {"jobs": w["jobs"]} for p, w in expected.items()}, runs, jobs, steps, elapsed, timeout)
        if verdict != "wait":
            print("scope=%s expected=%s" % (detection["scope"], ", ".join(sorted(expected))))
            print("\n".join(lines))
            print("Required CI Gate: " + verdict.upper())
            return 0 if verdict == "pass" else 1
        time.sleep(20)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
