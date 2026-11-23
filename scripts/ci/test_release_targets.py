import unittest

from release_targets import targets


def only(*apps):
    return {a: a in apps for a in ("consumer", "executor", "admin", "partner")}


class ReleaseTargetsTest(unittest.TestCase):
    def test_backend_and_docs_build_nothing(self):
        self.assertEqual(targets(["backend/pom.xml", "docs/a.md"]), only())

    def test_shared_mobile_change_builds_three_apps(self):
        self.assertEqual(targets(["mobile/lib/features/rides/a.dart"]), only("consumer", "executor", "admin"))

    def test_single_entrypoint(self):
        self.assertEqual(targets(["mobile/lib/executor_main.dart"]), only("executor"))
        self.assertEqual(targets(["mobile/lib/admin_rides_main.dart"]), only("admin"))

    def test_partner_only(self):
        self.assertEqual(targets(["partner_app/lib/x.dart"]), only("partner"))

    def test_design_package_and_workflow_build_all(self):
        everything = only("consumer", "executor", "admin", "partner")
        self.assertEqual(targets(["packages/kunde_design/lib/a.dart"]), everything)
        self.assertEqual(targets(["docs/x.md", ".github/workflows/android-release.yml"]), everything)


if __name__ == "__main__":
    unittest.main()
