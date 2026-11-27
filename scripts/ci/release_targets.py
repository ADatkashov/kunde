#!/usr/bin/env python3
"""Decide which signed DEV Android APKs a push to main must build.

Reads changed file paths (one per line) from stdin and prints a JSON object such as
{"consumer": true, "executor": true, "admin": true, "partner": false}.

Rules (conservative: when unsure, build):
  * apps/consumer/, apps/executor/, apps/admin/ and apps/partner/ are the four independent Flutter projects (independent Flutter projects);
  * a shared package affects exactly the apps that (transitively) depend on it, read from the pubspec.yaml files
    (detect_affected.flutter_graph; ADR-027); if that graph cannot be read, every app is built; the release workflows and
    this script affect every app;
  * backend, docs and other files build nothing.
"""
import json
import sys

APPS = ("consumer", "executor", "admin", "partner")
ALL_PREFIXES = (
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
)


def package_apps(path):
    """Apps that depend (transitively) on packages/<name>/...; every app when the graph is unusable (fail-safe)."""
    try:
        import detect_affected
        graph = detect_affected.flutter_graph()
        name = path.split("/")[1]
        if name not in graph:
            return APPS
        return tuple(a for a in APPS if a in detect_affected.dependents(graph, {name}))
    except Exception:
        return APPS


def targets(paths):
    out = dict.fromkeys(APPS, False)
    for path in (p.strip() for p in paths):
        if not path:
            continue
        specific = package_apps(path) if path.startswith("packages/") and path.count("/") >= 2 else \
            next((apps for prefix, apps in APP_PREFIXES if path.startswith(prefix)), None)
        if specific is not None:
            for app in specific:
                out[app] = True
        elif path.startswith(ALL_PREFIXES):
            return dict.fromkeys(APPS, True)
    return out


if __name__ == "__main__":
    print(json.dumps(targets(sys.stdin.read().splitlines())))
