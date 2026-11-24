#!/usr/bin/env python3
"""Decide which signed DEV Android APKs a push to main must build.

Reads changed file paths (one per line) from stdin and prints a JSON object such as
{"consumer": true, "executor": true, "admin": true, "partner": false}.

Rules (conservative: when unsure, build):
  * apps/consumer/, apps/executor/, apps/admin/ and apps/partner/ are the four independent Flutter projects (independent Flutter projects);
  * packages/kunde_operator is used only by Executor and Admin; any other shared package, the release workflows and
    this script affect every app;
  * backend, docs and other files build nothing.
"""
import json
import sys

APPS = ("consumer", "executor", "admin", "partner")
ALL_PREFIXES = (
    "packages/",
    ".github/workflows/android-release.yml",
    ".github/workflows/partner-release.yml",
    ".github/workflows/release-apk-on-merge.yml",
    "scripts/ci/release_targets.py",
)
APP_PREFIXES = (
    ("apps/consumer/", ("consumer",)),
    ("apps/executor/", ("executor",)),
    ("apps/admin/", ("admin",)),
    ("apps/partner/", ("partner",)),
    ("packages/kunde_operator/", ("executor", "admin")),
)


def targets(paths):
    out = dict.fromkeys(APPS, False)
    for path in (p.strip() for p in paths):
        if not path:
            continue
        specific = next((apps for prefix, apps in APP_PREFIXES if path.startswith(prefix)), None)
        if specific is not None:
            for app in specific:
                out[app] = True
        elif path.startswith(ALL_PREFIXES):
            return dict.fromkeys(APPS, True)
    return out


if __name__ == "__main__":
    print(json.dumps(targets(sys.stdin.read().splitlines())))
