#!/usr/bin/env python3
"""Required CI Gate (ADR-027): one always-running check that summarises the PR's other GitHub Actions checks.

Why polling and not `needs`: the PR checks live in separate path-filtered workflows (Backend CI, Flutter CI, Security CI, ...),
which a job cannot `needs`. The gate therefore reads the check runs of the PR head commit through the Checks API.

Verdict rules (evaluate):
  * a check of the ALWAYS set that does not exist (yet) -> WAIT (after the timeout -> FAIL "missing");
  * any other GitHub Actions check still queued/in_progress -> WAIT;
  * failure, cancelled, timed_out, action_required, stale, startup_failure -> FAIL;
  * success, skipped, neutral -> fine (a path-filtered workflow that did not trigger has no check at all, which is normal).
Only the latest run per check name counts (re-runs replace older results). The gate ignores itself and non-Actions checks.
Usage: required_gate.py <owner/repo> <head_sha> [timeout_seconds]; needs GH_TOKEN with `checks: read`.
"""
import json
import subprocess
import sys
import time

SELF = "Required CI Gate"
ALWAYS = ("configuration", "secrets", "dependencies", "containers")  # CI configuration + Security CI: no path filter
GOOD = {"success", "skipped", "neutral"}
SETTLE_SECONDS = 60  # late workflows register their checks a few seconds after the first ones


def latest_by_name(runs):
    latest = {}
    for run in runs:
        if run.get("app", {}).get("slug") != "github-actions" or run["name"] == SELF:
            continue
        if run["name"] not in latest or run["id"] > latest[run["name"]]["id"]:
            latest[run["name"]] = run
    return latest


def evaluate(runs, elapsed=0, timeout=2400):
    """-> (verdict, lines); verdict is 'pass', 'fail' or 'wait'."""
    latest = latest_by_name(runs)
    lines, bad, pending = [], [], []
    for name, run in sorted(latest.items()):
        if run["status"] != "completed":
            pending.append(name)
            lines.append("%-28s %s" % (name, run["status"]))
        elif run["conclusion"] in GOOD:
            lines.append("%-28s %s" % (name, run["conclusion"]))
        else:
            bad.append(name)
            lines.append("%-28s %s  <-- blocks merge" % (name, run["conclusion"]))
    missing = [n for n in ALWAYS if n not in latest]
    if bad:
        return "fail", lines
    if elapsed >= timeout and (pending or missing):
        lines.append("timed out after %ds waiting for: %s" % (elapsed, ", ".join(pending + missing)))
        return "fail", lines
    if pending or missing or elapsed < SETTLE_SECONDS:
        if missing:
            lines.append("waiting for required checks: " + ", ".join(missing))
        return "wait", lines
    return "pass", lines


def fetch(repo, sha):
    runs, page = [], 1
    while True:
        out = subprocess.check_output(["gh", "api", "repos/%s/commits/%s/check-runs?per_page=100&page=%d" % (repo, sha, page)], text=True)
        batch = json.loads(out)["check_runs"]
        runs += batch
        if len(batch) < 100:
            return runs
        page += 1


def main(argv):
    repo, sha = argv[1], argv[2]
    timeout = int(argv[3]) if len(argv) > 3 else 2400
    start = time.monotonic()
    while True:
        elapsed = int(time.monotonic() - start)
        verdict, lines = evaluate(fetch(repo, sha), elapsed, timeout)
        if verdict != "wait":
            print("\n".join(lines))
            print("Required CI Gate: " + verdict.upper())
            return 0 if verdict == "pass" else 1
        time.sleep(20)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
