import unittest

from release_targets import targets


def only(*apps):
    return {a: a in apps for a in ("consumer", "executor", "admin", "partner")}


class ReleaseTargetsTest(unittest.TestCase):
    def test_backend_and_docs_build_nothing(self):
        self.assertEqual(targets(["backend/build.gradle.kts", "docs/a.md"]), only())

    def test_each_app_builds_only_itself(self):
        self.assertEqual(targets(["apps/consumer/lib/features/rides/a.dart"]), only("consumer"))
        self.assertEqual(targets(["apps/executor/lib/main.dart"]), only("executor"))
        self.assertEqual(targets(["apps/admin/lib/main.dart"]), only("admin"))
        self.assertEqual(targets(["apps/partner/lib/x.dart"]), only("partner"))

    def test_operator_package_builds_its_dependents_incl_consumer(self):
        self.assertEqual(targets(["packages/kunde_operator/lib/operator_gate.dart"]), only("consumer", "executor", "admin"))

    def test_package_builds_only_the_apps_that_depend_on_it(self):
        self.assertEqual(targets(["packages/kunde_maps/lib/a.dart"]), only("consumer", "executor"))
        self.assertEqual(targets(["packages/kunde_ui/lib/a.dart"]), only("consumer", "executor", "admin", "partner"))
        self.assertEqual(targets(["packages/kunde_session/lib/a.dart"]), only("consumer", "executor", "admin", "partner"))

    def test_unknown_package_builds_everything(self):
        self.assertEqual(targets(["packages/not_a_package/lib/a.dart"]), only("consumer", "executor", "admin", "partner"))

    def test_other_shared_packages_and_workflows_build_all(self):
        everything = only("consumer", "executor", "admin", "partner")
        self.assertEqual(targets(["packages/kunde_auth/lib/a.dart"]), everything)
        self.assertEqual(targets(["docs/x.md", ".github/workflows/android-release.yml"]), everything)

    def test_combination_of_specific_changes(self):
        self.assertEqual(targets(["apps/admin/a.dart", "apps/consumer/b.dart"]), only("consumer", "admin"))


if __name__ == "__main__":
    unittest.main()
