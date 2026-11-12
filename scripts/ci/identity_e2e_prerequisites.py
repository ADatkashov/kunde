"""Fail the native E2E gate when its executable scenario is unavailable."""
import json
import os
from pathlib import Path


REQUIRED = (
    "backend/src/main/java/kz/kunde/identity/ConsumerIdentityController.java",
    "scripts/ci/start_identity_test_stack.sh",
    "scripts/ci/run_consumer_identity_e2e.sh",
    "scripts/ci/stop_identity_test_stack.sh",
    "scripts/ci/native_identity_stack.py",
    "scripts/ci/consumer_native_e2e.py",
    "docs/identity/consumer-validation/realm.json",
)


def check(root):
    missing = [name for name in REQUIRED if not (root / name).is_file()]
    return {
        "status": "BLOCKED_MISSING_IMPLEMENTATION" if missing else "PREREQUISITES_PRESENT",
        "nativeE2E": "NOT_EXECUTED",
        "missing": missing,
    }


def main():
    result = check(Path.cwd())
    ready = not result["missing"]
    Path("reports").mkdir(exist_ok=True)
    Path("reports/e2e-status.json").write_text(json.dumps(result, indent=2) + "\n")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"ready={str(ready).lower()}\n")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(f"Native E2E: {result['status']}; NOT_EXECUTED.\n")
    return 0 if ready else 1


if __name__ == "__main__":
    raise SystemExit(main())
