import pathlib
import unittest

import detect_affected as da
from product_api_e2e_args import args

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ProductApiE2EArgsTest(unittest.TestCase):
    def test_home_services_is_selective(self):
        self.assertEqual(args("home-services"), [":services:homeservices:test", ":app:test", "--tests", "kz.kunde.homeservices.*"])

    def test_product_without_app_tests_runs_module_tests_only(self):
        self.assertEqual(args("events"), [":services:events:test"])

    def test_all_covers_every_product_module(self):
        a = args("all")
        for module in da.backend_graph():
            if module not in ("app", "platform", "identity", "partners", "booking", "support", "admin", "maps"):
                self.assertIn(":services:%s:test" % module, a)

    def test_unknown_product_rejected(self):
        with self.assertRaises(ValueError):
            args("nope")

    def test_every_registered_test_package_has_tests_in_app(self):
        tests = ROOT / "backend/app/src/test/java/kz/kunde"
        for name, p in da.load_registry()["products"].items():
            for pkg in p["app_test_packages"]:
                self.assertTrue((tests / pkg).is_dir(), "%s: no tests in :app for package %s" % (name, pkg))


if __name__ == "__main__":
    unittest.main()
