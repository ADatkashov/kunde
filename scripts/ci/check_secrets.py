"""Bounded tracked-source marker scan, not complete secret discovery."""
import pathlib, re, subprocess, sys

PATTERNS = [re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
            re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b"),
            re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")]
MAX_BYTES = 2 * 1024 * 1024


def find_hits(names, root=pathlib.Path(".")):
    hits = []
    for name in names:
        if not name:
            continue
        p = root / name
        if not p.is_file() or p.stat().st_size > MAX_BYTES:
            continue
        data = p.read_bytes()
        if any(pattern.search(data) for pattern in PATTERNS):
            hits.append(name)
    return hits


def main():
    names = subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0")
    hits = find_hits(names)
    if hits:
        print("Potential secret markers; content withheld:", ", ".join(hits))
        return 1
    print("No selected secret markers in bounded tracked files; history/entropy coverage unverified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
