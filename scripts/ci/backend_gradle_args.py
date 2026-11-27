#!/usr/bin/env python3
"""Turn a detect_affected.py result into Gradle arguments for Backend CI (ADR-027); one argument per output line.

full      -> `clean build` (exactly what ran before the detector).
selective -> `assemble testClasses` (every module and its tests still compile, the executable JAR is still built for the
             smoke test) plus tests only for affected modules, the affected packages of :app and the architecture fitness tests.
skip      -> nothing (no backend input changed); the caller still runs the job so the required check never goes missing.
Usage: backend_gradle_args.py <result.json>   (first line printed is the mode)
"""
import json
import sys

ARCH = "kz.kunde.architecture.*"


def gradle_args(result):
    backend = result["backend"]
    if result.get("full") or result.get("scope") == "full":
        return "full", ["clean", "build"]
    if not backend.get("run"):
        return "skip", []
    args = ["assemble", "testClasses"]
    args += backend["gradle_tasks"]
    args.append(":app:test")
    if backend["app_tests"] != "all":
        for pkg in sorted(set(backend.get("app_test_packages", []))):
            args += ["--tests", "kz.kunde.%s.*" % pkg]
        args += ["--tests", ARCH]
    return "selective", args


if __name__ == "__main__":
    mode, args = gradle_args(json.load(open(sys.argv[1], encoding="utf-8")))
    print(mode)
    print("\n".join(args))
