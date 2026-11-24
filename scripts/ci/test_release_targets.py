import unittest

from release_targets import targets


def only(*apps):
    return {a: a in apps for a in ("consumer", "executor", "admin", "partner")}


class ReleaseTargetsTest(unittest.TestCase):
    def test_backend_and_docs_build_nothing(self):
        self.assertEqual(targets(["backend/build.gradle.kts", "docs/a.md"]), only())

    def test_each_app_builds_only_itself(self):
        self.assertEqual(targets(["mobile/lib/features/rides/a.dart"]), only("consumer"))
        self.assertEqual(targets(["apps/executor/lib/main.dart"]), only("executor"))
        self.assertEqual(targets(["apps/admin/lib/main.dart"]), only("admin"))
        self.assertEqual(targets(["partner_app/lib/x.dart"]), only("partner"))

    def test_operator_package_builds_the_two_operator_apps(self):
        self.assertEqual(targets(["packages/kunde_operator/lib/operator_gate.dart"]), only("executor", "admin"))

    def test_other_shared_packages_and_workflows_build_all(self):
        everything = only("consumer", "executor", "admin", "partner")
        self.assertEqual(targets(["packages/kunde_auth/lib/a.dart"]), everything)
        self.assertEqual(targets(["docs/x.md", ".github/workflows/android-release.yml"]), everything)

    def test_combination_of_specific_changes(self):
        self.assertEqual(targets(["apps/admin/a.dart", "mobile/b.dart"]), only("consumer", "admin"))


if __name__ == "__main__":
    unittest.main()
