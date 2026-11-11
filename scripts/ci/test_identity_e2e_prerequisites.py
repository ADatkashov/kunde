import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from identity_e2e_prerequisites import REQUIRED


class PrerequisitesTest(unittest.TestCase):
    def run_gate(self, present):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in present:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.touch()
            output = root / "output"
            summary = root / "summary"
            process = subprocess.run(
                [sys.executable, str(Path(__file__).with_name("identity_e2e_prerequisites.py"))],
                cwd=root,
                env={**os.environ, "GITHUB_OUTPUT": str(output), "GITHUB_STEP_SUMMARY": str(summary)},
                capture_output=True, text=True,
            )
            return process.returncode, json.loads((root / "reports/e2e-status.json").read_text()), output.read_text()

    def test_each_missing_prerequisite_blocks_execution(self):
        for missing in REQUIRED:
            with self.subTest(missing=missing):
                code, report, output = self.run_gate(set(REQUIRED) - {missing})
                self.assertEqual(code, 1)
                self.assertEqual(report["missing"], [missing])
                self.assertEqual(report["status"], "BLOCKED_MISSING_IMPLEMENTATION")
                self.assertEqual(report["nativeE2E"], "NOT_EXECUTED")
                self.assertEqual(output, "ready=false\n")

    def test_presence_allows_execution_without_claiming_e2e_success(self):
        code, report, output = self.run_gate(REQUIRED)
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "PREREQUISITES_PRESENT")
        self.assertEqual(report["nativeE2E"], "NOT_EXECUTED")
        self.assertEqual(output, "ready=true\n")
