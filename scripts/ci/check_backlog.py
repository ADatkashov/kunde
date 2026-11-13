#!/usr/bin/env python3
"""Validate the roadmap backlog files (docs/roadmap/backlog/*.yaml).

The files hold JSON. This gate fails when a file does not parse, when the canonical task set
TASK-001..TASK-056 is not exactly present once, when a task has no valid dependency list or
refers to an unknown task, or when an implementation_status is outside the known set.
It never promotes or changes a status.
"""
import json
import pathlib
import re
import sys

BACKLOG = pathlib.Path("docs/roadmap/backlog")
FILES = ("tasks", "epics", "features", "releases", "risks", "dependencies")
CANONICAL = {f"TASK-{n:03d}" for n in range(1, 57)}
STATUSES = {"blocked", "implemented_verified", "in_progress", "not_started", "partially_verified"}
TASK_ID = re.compile(r"^TASK-\d{3}$")


def load(root, name):
    path = root / BACKLOG / f"{name}.yaml"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ValueError(f"{path}: not valid JSON ({error})") from error
    if not isinstance(data, list):
        raise ValueError(f"{path}: expected a JSON list")
    return data


def check_tasks(tasks):
    problems = []
    ids = [t.get("id") if isinstance(t, dict) else None for t in tasks]
    seen = set()
    for task_id in ids:
        if task_id in seen:
            problems.append(f"duplicate task id: {task_id}")
        seen.add(task_id)
    if seen != CANONICAL:
        missing = sorted(CANONICAL - seen)
        extra = sorted(str(i) for i in seen - CANONICAL)
        problems.append(f"canonical task set differs: missing={missing} extra={extra}")
    for task in tasks:
        if not isinstance(task, dict):
            problems.append("task entry is not an object")
            continue
        task_id = task.get("id")
        if not isinstance(task_id, str) or not TASK_ID.match(task_id):
            problems.append(f"invalid task id: {task_id!r}")
        if task.get("implementation_status") not in STATUSES:
            problems.append(f"{task_id}: unknown implementation_status {task.get('implementation_status')!r}")
        dependencies = task.get("dependencies")
        if not isinstance(dependencies, list):
            problems.append(f"{task_id}: dependencies must be a list")
            continue
        for dependency in dependencies:
            if dependency not in CANONICAL:
                problems.append(f"{task_id}: unknown dependency {dependency!r}")
            if dependency == task_id:
                problems.append(f"{task_id}: depends on itself")
    return problems


def run(root=pathlib.Path(".")):
    problems = []
    for name in FILES:
        try:
            data = load(root, name)
        except ValueError as error:
            problems.append(str(error))
            continue
        if name == "tasks":
            problems.extend(check_tasks(data))
    return problems


def main():
    problems = run()
    for problem in problems:
        print(f"backlog: {problem}")
    if problems:
        return 1
    print("backlog: all files parse and the 56 canonical tasks are consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
