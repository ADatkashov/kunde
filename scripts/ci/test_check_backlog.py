import json
import pathlib
import tempfile
import unittest

import check_backlog


def task(n, **over):
    base = {"id": f"TASK-{n:03d}", "implementation_status": "not_started", "dependencies": []}
    base.update(over)
    return base


class CheckBacklogTests(unittest.TestCase):
    def run_in(self, files):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            target = root / "docs/roadmap/backlog"
            target.mkdir(parents=True)
            for name in check_backlog.FILES:
                content = files.get(name, [])
                text = content if isinstance(content, str) else json.dumps(content)
                (target / f"{name}.yaml").write_text(text, encoding="utf-8")
            return check_backlog.run(root)

    def full(self):
        return [task(n) for n in range(1, 57)]

    def test_complete_consistent_backlog_passes(self):
        self.assertEqual(self.run_in({"tasks": self.full()}), [])

    def test_repository_backlog_passes(self):
        self.assertEqual(check_backlog.run(pathlib.Path(__file__).resolve().parents[2]), [])

    def test_unparseable_file_is_reported_with_its_name(self):
        problems = self.run_in({"tasks": self.full(), "risks": '[{"id": "R", "x": "a "quoted" b"}]'})
        self.assertEqual(len(problems), 1)
        self.assertIn("risks.yaml", problems[0])
        self.assertIn("not valid JSON", problems[0])

    def test_missing_duplicate_and_extra_tasks_are_reported(self):
        tasks = self.full()[:-1] + [task(1), task(99)]
        text = " ".join(self.run_in({"tasks": tasks}))
        self.assertIn("duplicate task id: TASK-001", text)
        self.assertIn("missing=['TASK-056']", text)
        self.assertIn("TASK-099", text)

    def test_unknown_status_dependency_and_self_dependency_are_reported(self):
        tasks = self.full()
        tasks[0] = task(1, implementation_status="done")
        tasks[1] = task(2, dependencies=["TASK-777", "TASK-002"])
        tasks[2] = task(3, dependencies="TASK-001")
        text = " ".join(self.run_in({"tasks": tasks}))
        self.assertIn("unknown implementation_status 'done'", text)
        self.assertIn("unknown dependency 'TASK-777'", text)
        self.assertIn("TASK-002: depends on itself", text)
        self.assertIn("TASK-003: dependencies must be a list", text)


if __name__ == "__main__":
    unittest.main()
