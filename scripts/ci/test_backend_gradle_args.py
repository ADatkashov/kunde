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

    def test_every_selective_module_task_exists_in_gradle(self):
        _, a = args("backend/services/booking/src/main/java/A.java")
        modules = da.backend_graph()
        for task in (t for t in a if t.startswith(":services:")):
            self.assertIn(task.split(":")[2], modules)


if __name__ == "__main__":
    unittest.main()
