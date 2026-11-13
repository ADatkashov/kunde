"""Fail-closed policy checks for infrastructure/terraform (no cloud access needed)."""
import pathlib, re, subprocess, sys

FORBIDDEN_TRACKED = re.compile(r"(\.tfstate(\.backup)?$|\.tfvars$|\.tfplan$|(^|/)\.terraform/|(^|/)backend\.hcl$)")
RULES = [
    (re.compile(r"sslmode=(disable|allow|prefer)"), "database TLS must not be weakened"),
    (re.compile(r"postgres(ql)?://[^@\s:/]+:[^@\s]+@"), "connection string with embedded credentials"),
    (re.compile(r"(?i)\b(api_key|password|secret|token)\s*=\s*\"[^\"$]{3,}\""), "literal credential in HCL"),
    (re.compile(r"-auto-approve"), "auto-approve is only allowed in the reviewed apply workflow"),
    (re.compile(r"terraform\s+destroy"), "destroy must not run from automation"),
]
ALLOW_AUTO_APPROVE = {".github/workflows/terraform-dev.yml"}


def check(files):
    """files: iterable of (path, text). Returns list of violations."""
    problems = []
    for path, text in files:
        if path.endswith(".tf") or path.endswith(".hcl"):
            text = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
        if FORBIDDEN_TRACKED.search(path):
            problems.append(f"{path}: state/plan/var/backend file must not be tracked")
            continue
        for pattern, message in RULES:
            if pattern.search(text):
                if message.startswith("database TLS") and path.endswith(".tftest.hcl"):
                    continue  # negative test cases must name the weak value
                if message.startswith("auto-approve") and path in ALLOW_AUTO_APPROVE:
                    continue
                if message.startswith("destroy") and path.startswith("scripts/ci/"):
                    continue
                problems.append(f"{path}: {message}")
    return problems


def tracked_files():
    names = subprocess.check_output(["git", "ls-files"], text=True).splitlines()
    for name in names:
        if name.startswith(("infrastructure/terraform/", ".github/workflows/terraform")) or FORBIDDEN_TRACKED.search(name):
            p = pathlib.Path(name)
            yield name, p.read_text(errors="ignore") if p.is_file() else ""


if __name__ == "__main__":
    found = check(tracked_files())
    for line in found:
        print(line)
    sys.exit(1 if found else 0)
