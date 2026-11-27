#!/usr/bin/env python3
"""Affected-modules detector (ADR-027): which products, Gradle modules and Flutter apps a change touches.

Fail-safe by design: an unknown file, an invalid dependency graph or unresolvable base/head SHAs yield scope FULL
(every check runs) with the reason recorded. Nothing is ever skipped silently.

  detect_affected.py --base <sha> --head <sha> [--merge-base]   # git diff -M --name-status
  detect_affected.py --files-from -                             # paths on stdin (tests, local use)
  detect_affected.py --print-graph                              # computed Gradle/Flutter graph

Prints one JSON document; with GITHUB_OUTPUT set also writes `scope` and `result` outputs.
Dependency edges are read from backend/settings.gradle.kts, backend/**/build.gradle.kts and apps|packages/*/pubspec.yaml.
Stdlib only.
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
REGISTRY = pathlib.Path(__file__).with_name("product-registry.json")
APPS = ("consumer", "executor", "admin", "partner")


class GraphError(Exception):
    pass


def load_registry():
    return json.loads(REGISTRY.read_text(encoding="utf-8"))


def backend_graph(root=ROOT):
    """module -> set(direct project dependencies), from settings + build files."""
    settings = (root / "backend/settings.gradle.kts").read_text(encoding="utf-8")
    included = re.findall(r'":(?:services:)?([a-z0-9-]+)"', " ".join(re.findall(r"include\((.*?)\)", settings, re.S)))
    graph = {}
    for module in included:
        path = root / ("backend/" + module if module in ("app", "platform") else "backend/services/" + module) / "build.gradle.kts"
        if not path.is_file():
            raise GraphError("missing build file for module " + module)
        text = re.sub(r"//.*", "", path.read_text(encoding="utf-8"))
        graph[module] = set(re.findall(r'project\(":(?:services:)?([a-z0-9-]+)"\)', text))
    for module, deps in graph.items():
        if not deps <= set(graph):
            raise GraphError("%s depends on unknown module(s) %s" % (module, sorted(deps - set(graph))))
    return graph


def flutter_graph(root=ROOT):
    """project (app name or package name) -> set(direct package dependencies)."""
    graph = {}
    projects = [(a, root / "apps" / a) for a in APPS] + [(p.name, p) for p in sorted((root / "packages").iterdir()) if p.is_dir()]
    for name, path in projects:
        pubspec = path / "pubspec.yaml"
        if not pubspec.is_file():
            raise GraphError("missing pubspec.yaml for " + name)
        graph[name] = set(re.findall(r"path:\s*\.\./(?:\.\./packages/)?([A-Za-z0-9_]+)\s*$", pubspec.read_text(encoding="utf-8"), re.M))
    for name, deps in graph.items():
        if not deps <= set(graph):
            raise GraphError("%s depends on unknown package(s) %s" % (name, sorted(deps - set(graph))))
    return graph


def check_acyclic(graph, label):
    state = {}

    def visit(node):
        if state.get(node) == 1:
            raise GraphError("cycle in %s graph at %s" % (label, node))
        if state.get(node) == 2:
            return
        state[node] = 1
        for dep in graph[node]:
            visit(dep)
        state[node] = 2

    for node in graph:
        visit(node)


def dependents(graph, seeds):
    """seeds plus everything that (transitively) depends on them."""
    result = set(seeds)
    changed = True
    while changed:
        changed = False
        for node, deps in graph.items():
            if node not in result and deps & result:
                result.add(node)
                changed = True
    return result


class Detector:
    def __init__(self, registry=None, root=ROOT):
        self.registry = registry or load_registry()
        self.backend = backend_graph(root)
        self.flutter = flutter_graph(root)
        check_acyclic(self.backend, "backend")
        check_acyclic(self.flutter, "flutter")
        reg = self.registry
        self.shared = reg["backend_shared"]
        self.products = reg["products"]
        self.module_product = {p["backend"]: name for name, p in self.products.items()}
        registered = set(self.shared) | set(self.module_product) | {"app"}
        if registered != set(self.backend):
            raise GraphError("registry and settings.gradle.kts disagree: %s" % sorted(registered ^ set(self.backend)))
        self.feature_owner = {}  # (app, feature dir) -> product or None for shared
        for name, p in self.products.items():
            for app, dirs in p["flutter"].items():
                for d in dirs:
                    self.feature_owner[(app, d)] = name
        for app, cfg in reg["flutter_apps"].items():
            for d in cfg["shared_features"]:
                self.feature_owner[(app, d)] = None

    def detect(self, paths):
        reasons = []
        full = []
        modules, packages, products, flutter_all, flutter_feats = set(), set(), set(), set(), {}
        app_all = False
        migration = docker = docs = infra = False

        def feat(app, d):
            if (app, d) in self.feature_owner:
                owner = self.feature_owner[(app, d)]
                if owner is None:
                    flutter_all.add(app)
                    reasons.append("%s: shared feature %s/%s -> whole app" % (app, app, d))
                else:
                    flutter_feats.setdefault(app, set()).add(d)
                    products.add(owner)
            else:
                flutter_all.add(app)
                reasons.append("%s: unregistered feature dir %s -> whole app" % (app, d))

        for path in sorted(set(paths)):
            parts = path.split("/")
            if path.startswith((".github/", "scripts/ci/", "compose.yaml")) or path in ("backend/build.gradle.kts", "backend/settings.gradle.kts") or path.startswith("backend/gradle/"):
                full.append("%s: Gradle/CI/build configuration" % path)
            elif path.startswith("backend/") and len(parts) == 2 and path.endswith(".md"):
                docs = True
            elif path == "backend/Dockerfile":
                docker = True
                reasons.append(path + ": docker image build")
            elif path.startswith("backend/app/src/main/resources/db/migration/"):
                migration = app_all = True
                products |= set(self.products)
                reasons.append(path + ": Flyway migration -> app tests, every product (conservative)")
            elif path.startswith("backend/platform/") or path.startswith("backend/services/") or path.startswith("backend/app/"):
                if path.startswith("backend/platform/"):
                    mod = "platform"
                elif path.startswith("backend/services/") and len(parts) > 3:
                    mod = parts[2]
                elif path.startswith("backend/app/"):
                    mod = "app"
                else:
                    mod = None
                if mod not in self.backend:
                    full.append("%s: unknown backend module" % path)
                    continue
                modules.add(mod)
                reasons.append("%s: backend module %s" % (path, mod))
                if mod == "app":
                    t = re.match(r"backend/app/src/test/java/kz/kunde/([a-z0-9]+)/", path)
                    pkg_owner = next((n for n, p in self.products.items() if t and t.group(1) in p["app_test_packages"]), None)
                    if pkg_owner:
                        products.add(pkg_owner)
                    else:
                        app_all = True
            elif parts[0] == "apps" and len(parts) > 2 and parts[1] in APPS:
                app = parts[1]
                if len(parts) > 4 and parts[2] in ("lib", "test") and parts[3] == "features":
                    feat(app, parts[4])
                else:
                    flutter_all.add(app)
                    reasons.append("%s: %s application-level file -> whole app" % (path, app))
            elif parts[0] == "packages" and len(parts) > 2 and parts[1] in self.flutter:
                packages.add(parts[1])
                reasons.append("%s: shared package %s" % (path, parts[1]))
            elif path.startswith("infrastructure/"):
                infra = True
                reasons.append(path + ": infrastructure (own workflows)")
            elif path.startswith(("docs/", "reports/")) or (len(parts) == 1 and path.endswith(".md")) or path in ("LICENSE", ".gitignore"):
                docs = True
            elif path.startswith("scripts/dev/"):
                reasons.append(path + ": DEV smoke script (CI configuration checks only)")
            elif path.startswith("scripts/admin-web/"):
                flutter_all.add("admin")
                reasons.append(path + ": admin web build -> admin app")
            else:
                full.append("%s: unknown component" % path)

        if full:
            return self._full(full)

        # Backend: changed modules plus everything that (transitively) depends on them. Composition-root integration tests
        # (:app) run for the affected products' packages; platform/identity/partners reach every domain, so all of them run.
        direct = modules - {"app"}
        aff_modules = dependents(self.backend, direct) if direct else set()
        if modules:
            aff_modules.add("app")
        for m in aff_modules & set(self.shared):
            if self.shared[m].get("app_tests_all"):
                app_all = True
                reasons.append("shared module %s -> all :app integration tests" % m)
        backend_products = {self.module_product[m] for m in aff_modules if m in self.module_product}
        task_modules = sorted(aff_modules - {"app"})
        app_packages = sorted({pkg for p in backend_products | products for pkg in self.products[p]["app_test_packages"]}
                              | {pkg for m in aff_modules if m in self.shared for pkg in self.shared[m]["app_test_packages"]})

        # Flutter: package changes reach every app that (transitively) depends on them.
        aff_proj = dependents(self.flutter, packages) if packages else set()
        flutter_all |= aff_proj & set(APPS)
        # A backend product change pulls in that product's Flutter feature tests (clients of its API contract).
        for p in backend_products:
            for app, dirs in self.products[p]["flutter"].items():
                flutter_feats.setdefault(app, set()).update(dirs)
        flutter = {}
        for app in APPS:
            selective = self.registry["flutter_apps"][app]["selective_tests"]
            if app in flutter_all or (app in flutter_feats and not selective):
                flutter[app] = {"mode": "all", "features": []}
            elif app in flutter_feats:
                flutter[app] = {"mode": "selective", "features": sorted(flutter_feats[app])}
        products |= backend_products
        touched = bool(products or packages or modules or flutter or migration or docker or infra)
        scope = "selective" if touched else ("docs" if docs else "none")
        run_backend = bool(aff_modules or migration or docker)
        return {
            "scope": scope, "full": False, "reasons": reasons,
            "backend": {"modules": task_modules, "gradle_tasks": [":services:%s:test" % m for m in task_modules],
                        "app_tests": "all" if app_all else (app_packages or ("architecture-only" if run_backend else "none")),
                        "app_test_packages": [] if app_all else app_packages, "migration": migration, "docker": docker,
                        "run": run_backend},
            "flutter": {"apps": flutter, "packages": sorted(aff_proj - set(APPS)), "run": bool(flutter or aff_proj)},
            "products": {"affected": sorted(products), "skipped": {p: "not affected" for p in sorted(set(self.products) - products)}},
            "docs": docs, "infra": infra,
        }

    def _full(self, why):
        return {"scope": "full", "full": True, "reasons": why,
                "backend": {"modules": sorted(self.backend), "gradle_tasks": ["test"], "app_tests": "all", "app_test_packages": [], "migration": True, "docker": True, "run": True},
                "flutter": {"apps": {a: {"mode": "all", "features": []} for a in APPS}, "packages": sorted(set(self.flutter) - set(APPS)), "run": True},
                "products": {"affected": sorted(self.products), "skipped": {}}, "docs": True, "infra": True}


def summary_markdown(result):
    """Short human-readable decision for $GITHUB_STEP_SUMMARY."""
    lines = ["### Affected modules (ADR-027)", "", "- scope: **%s**" % result["scope"],
             "- backend: modules `%s`, :app tests `%s`" % (", ".join(result["backend"]["modules"]) or "-", result["backend"]["app_tests"]),
             "- products affected: %s" % (", ".join(result["products"]["affected"]) or "-"),
             "- products skipped: %s" % (", ".join(result["products"]["skipped"]) or "-"), ""]
    lines += ["- " + r.replace("|", "\\|") for r in result["reasons"][:30]]
    return "\n".join(lines) + "\n"


def full_fallback(reason):
    """Result used when the detector cannot be trusted: everything runs."""
    return {"scope": "full", "full": True, "reasons": [reason],
            "backend": {"modules": [], "gradle_tasks": ["test"], "app_tests": "all", "app_test_packages": [], "migration": True, "docker": True, "run": True},
            "flutter": {"apps": {a: {"mode": "all", "features": []} for a in APPS}, "packages": [], "run": True},
            "products": {"affected": [], "skipped": {}}, "docs": True, "infra": True}


def changed_paths(base, head, merge_base=False):
    sha = re.compile(r"[0-9a-f]{40}")
    if not (sha.fullmatch(base or "") and sha.fullmatch(head or "")) or set(base) == {"0"}:
        raise ValueError("base/head SHAs are not usable (%r, %r)" % (base, head))
    rng = base + "..." + head if merge_base else base + ".." + head
    out = subprocess.check_output(["git", "diff", "--name-status", "-M", "-z", rng], cwd=ROOT, text=True, stderr=subprocess.PIPE)
    fields, paths, i = out.split("\0"), [], 0
    while i < len(fields) and fields[i]:
        status = fields[i]
        n = 2 if status[0] in "RC" else 1
        paths += fields[i + 1:i + 1 + n]  # renames/copies contribute both the old and the new path
        i += 1 + n
    return paths


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--base")
    ap.add_argument("--head")
    ap.add_argument("--merge-base", action="store_true", help="diff base...head (pull requests)")
    ap.add_argument("--files-from", help="'-' reads one path per line from stdin")
    ap.add_argument("--print-graph", action="store_true")
    ap.add_argument("--result-file", help="also write the JSON result to this file")
    ap.add_argument("--summary", action="store_true", help="append a Markdown summary to $GITHUB_STEP_SUMMARY")
    args = ap.parse_args(argv)
    try:
        if args.print_graph:
            print(json.dumps({"backend": {k: sorted(v) for k, v in backend_graph().items()},
                              "flutter": {k: sorted(v) for k, v in flutter_graph().items()}}, indent=2, sort_keys=True))
            return 0
        if args.files_from:
            paths = [p.strip() for p in sys.stdin.read().splitlines() if p.strip()]
        else:
            paths = changed_paths(args.base, args.head, args.merge_base)
        result = Detector().detect(paths)
        result["files"] = len(paths)
    except (GraphError, ValueError, subprocess.CalledProcessError, OSError) as exc:
        result = full_fallback("detector failed, FULL CI (fail-safe): %s" % exc)
    text = json.dumps(result, indent=2, sort_keys=True)
    print(text)
    if args.result_file:
        pathlib.Path(args.result_file).write_text(text + "\n", encoding="utf-8")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if args.summary and summary:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write(summary_markdown(result))
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a", encoding="utf-8") as fh:
            fh.write("scope=%s\nresult=%s\n" % (result["scope"], json.dumps(result, sort_keys=True)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
