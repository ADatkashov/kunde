"""Bounded tracked-source marker scan, not complete secret discovery."""
import pathlib, re, subprocess, sys
patterns = [re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
            re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b"),
            re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")]
hits = []
for name in subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0"):
    if not name: continue
    p = pathlib.Path(name)
    if not p.is_file() or p.stat().st_size > 2 * 1024 * 1024: continue
    data = p.read_bytes()
    if any(pattern.search(data) for pattern in patterns): hits.append(name)
if hits:
    print("Potential secret markers; content withheld:", ", ".join(hits))
    sys.exit(1)
print("No selected secret markers in bounded tracked files; history/entropy coverage unverified")
