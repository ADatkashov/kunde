#!/usr/bin/env python3
"""Decide which signed DEV Android APKs a push to main must build.

Reads changed file paths (one per line) from stdin and prints a JSON object such as
{"consumer": true, "executor": true, "admin": true, "partner": false}.

Rules (conservative: when unsure, build):
  * packages/kunde_design, the release workflows and this script affect every app;
  * partner_app/** affects only Partner;
  * mobile/** is one shared Flutter codebase for Consumer, Executor and Admin, so a shared change builds all three;
    a change confined to one entry point (executor_main.dart / admin_rides_main.dart / main.dart) builds only that app;
  * backend, docs and other files build nothing.
"""
import json
import sys

APPS = ("consumer", "executor", "admin", "partner")
ALL_PREFIXES = (
    "packages/kunde_design/",
    ".github/workflows/android-release.yml",
    ".github/workflows/partner-release.yml",
    ".github/workflows/release-apk-on-merge.yml",
    "scripts/ci/release_targets.py",
)
ENTRYPOINTS = {
    "mobile/lib/executor_main.dart": "executor",
    "mobile/lib/admin_rides_main.dart": "admin",
    "mobile/lib/main.dart": "consumer",
}


def targets(paths):
    out = dict.fromkeys(APPS, False)
    for path in (p.strip() for p in paths):
        if not path:
            continue
        if path.startswith(ALL_PREFIXES):
            return dict.fromkeys(APPS, True)
        if path.startswith("partner_app/"):
            out["partner"] = True
        elif path in ENTRYPOINTS:
            out[ENTRYPOINTS[path]] = True
        elif path.startswith("mobile/"):
            for app in ("consumer", "executor", "admin"):
                out[app] = True
    return out


if __name__ == "__main__":
    print(json.dumps(targets(sys.stdin.read().splitlines())))
