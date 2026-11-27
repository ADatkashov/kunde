#!/usr/bin/env python3
"""Per-app Flutter CI selection from a detect_affected.py result (ADR-027). Prints GITHUB_OUTPUT-style lines.

mode=all        run the whole app suite (previous behaviour) - also for FULL, shared/app-level changes
mode=selective  run only `tests` (existing test/features/<dir> directories of affected features)
mode=skip       the change cannot reach this app: no analyze/test (the job still succeeds, the required check exists)
packages=       space separated shared packages to analyze/test (affected ones; everything in FULL)
Selective never replaces `flutter analyze`: it still compiles every feature of the app. Usage: flutter_selection.py <result.json> <app>
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOKEN = re.compile(r"[A-Za-z0-9_./-]+")


def selection(result, app, root=ROOT):
    flutter = result["flutter"]
    packages = sorted(flutter.get("packages", []))
    if result.get("full") or result.get("scope") == "full":
        return {"mode": "all", "tests": [], "packages": packages}
    cfg = flutter["apps"].get(app)
    if cfg is None:
        return {"mode": "skip", "tests": [], "packages": packages}
    if cfg["mode"] == "all":
        return {"mode": "all", "tests": [], "packages": packages}
    tests = [f"test/features/{d}" for d in cfg["features"] if (root / "apps" / app / "test" / "features" / d).is_dir()]
    return {"mode": "selective", "tests": tests, "packages": packages}


if __name__ == "__main__":
    out = selection(json.load(open(sys.argv[1], encoding="utf-8")), sys.argv[2])
    for key in ("tests", "packages"):
        assert all(TOKEN.fullmatch(v) for v in out[key]), out
    print("mode=" + out["mode"])
    print("tests=" + " ".join(out["tests"]))
    print("packages=" + " ".join(out["packages"]))
