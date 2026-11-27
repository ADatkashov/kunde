import unittest

import detect_affected as da
from backend_gradle_args import gradle_args

D = da.Detector()


def args(*paths):
    return gradle_args(D.detect(list(paths)))


class BackendGradleArgsTest(unittest.TestCase):
    def test_full_is_the_previous_clean_build(self):
        self.assertEqual(args("weird.bin"), ("full", ["clean", "build"]))
        self.assertEqual(gradle_args(da.full_fallback("x")), ("full", ["clean", "build"]))

    def test_home_services_runs_only_its_tests_but_compiles_everything(self):
        mode, a = args("backend/services/homeservices/src/main/java/kz/kunde/homeservices/A.java")
        self.assertEqual(mode, "selective")
        self.assertEqual(a[:2], ["assemble", "testClasses"])
        self.assertIn(":services:homeservices:test", a)
        self.assertNotIn(":services:rides:test", a)
        self.assertIn("kz.kunde.homeservices.*", a)
        self.assertIn("kz.kunde.architecture.*", a)
        self.assertNotIn("kz.kunde.rides.*", a)
        # --tests must follow :app:test, otherwise Gradle would attach it to another task
        self.assertLess(a.index(":app:test"), a.index("--tests"))

    def test_shared_module_runs_all_app_tests_without_filters(self):
        mode, a = args("backend/platform/src/main/java/kz/kunde/platform/A.java")
        self.assertEqual(mode, "selective")
        self.assertIn(":app:test", a)
        self.assertNotIn("--tests", a)

    def test_migration_runs_all_app_tests(self):
        mode, a = args("backend/app/src/main/resources/db/migration/V77__x.sql")
        self.assertEqual(mode, "selective")
        self.assertIn(":app:test", a)
        self.assertNotIn("--tests", a)

    def test_no_backend_input_skips_gradle(self):
        self.assertEqual(args("backend/README.md"), ("skip", []))
        self.assertEqual(args("docs/a.md"), ("skip", []))

    def test_platform_module_has_its_own_gradle_path(self):
        # regression: ':services:platform:test' does not exist, the project is ':platform' (PR 296)
        _, a = args("backend/platform/src/main/java/kz/kunde/platform/partner/PartnerDirectory.java")
        self.assertIn(":platform:test", a)
        self.assertNotIn(":services:platform:test", a)

    def test_every_module_maps_to_a_project_declared_in_settings(self):
        import pathlib
        import re
        settings = (pathlib.Path(__file__).resolve().parents[2] / "backend/settings.gradle.kts").read_text(encoding="utf-8")
        declared = set(re.findall(r'"(:[a-z:]+)"', " ".join(re.findall(r"include\((.*?)\)", settings, re.S))))
        for module in da.backend_graph():
            self.assertIn(da.gradle_project(module), declared, module)
        for path in ("backend/platform/src/A.java", "backend/services/identity/src/A.java", "backend/app/src/main/A.java"):
            _, a = args(path)
            for task in (t for t in a if t.endswith(":test") and t.startswith(":")):
                self.assertIn(task[:-len(":test")], declared, task)

    def test_every_selective_module_task_exists_in_gradle(self):
        _, a = args("backend/services/booking/src/main/java/A.java")
        modules = da.backend_graph()
        for task in (t for t in a if t.startswith(":services:")):
            self.assertIn(task.split(":")[2], modules)


if __name__ == "__main__":
    unittest.main()
