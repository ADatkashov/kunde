import io
import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

import check_secrets

# Markers are assembled at runtime so this file itself never matches the scanner.
PEM = "-----BEGIN " + "RSA PRIVATE KEY-----"
GITHUB_TOKEN = "gh" + "p_" + "a" * 36
FINE_GRAINED = "github" + "_pat_" + "A1" * 25
AWS_KEY = "AK" + "IA" + "B" * 16


class CheckSecretsTests(unittest.TestCase):
    def scan(self, files):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for name, content in files.items():
                (root / name).write_bytes(content if isinstance(content, bytes) else content.encode())
            return check_secrets.find_hits(list(files), root)

    def test_detects_each_marker_family_and_names_only_the_file(self):
        files = {"key.pem": PEM, "token.txt": "x=" + GITHUB_TOKEN, "pat.txt": FINE_GRAINED, "aws.env": AWS_KEY,
                 "clean.txt": "nothing to see"}
        self.assertEqual(self.scan(files), ["key.pem", "token.txt", "pat.txt", "aws.env"])

    def test_ignores_near_misses_missing_and_oversized_files(self):
        near_miss = {"short.txt": "ghp_" + "a" * 10, "word.txt": "BEGIN PRIVATE KEY", "aws.txt": "AKIA" + "B" * 5}
        self.assertEqual(self.scan(near_miss), [])
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "big.bin").write_bytes(PEM.encode() + b"\0" * check_secrets.MAX_BYTES)
            self.assertEqual(check_secrets.find_hits(["big.bin", "missing.txt", ""], root), [])

    def run_main(self, tracked, hits):
        output = io.StringIO()
        with patch("check_secrets.subprocess.check_output", return_value=tracked), \
             patch("check_secrets.find_hits", return_value=hits), redirect_stdout(output):
            return check_secrets.main(), output.getvalue()

    def test_main_fails_closed_without_echoing_secret_content(self):
        code, output = self.run_main(b"a.txt\0b.txt\0", ["a.txt"])
        self.assertEqual(code, 1)
        self.assertIn("a.txt", output)
        self.assertIn("content withheld", output)
        for secret in (PEM, GITHUB_TOKEN, AWS_KEY):
            self.assertNotIn(secret, output)

    def test_main_passes_and_states_the_limits_of_the_scan(self):
        code, output = self.run_main(b"a.txt\0", [])
        self.assertEqual(code, 0)
        self.assertIn("history/entropy coverage unverified", output)


if __name__ == "__main__":
    unittest.main()
