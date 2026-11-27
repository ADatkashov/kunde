import json
import pathlib
import unittest

from product_e2e_plan import SUITES, plan

WORKFLOWS = pathlib.Path(__file__).resolve().parents[2] / ".github/workflows"


class ProductE2EPlanTest(unittest.TestCase):
    def test_taxi_multi_role_runs_only_rides(self):
        self.assertEqual(plan("taxi", "multi-role"), {"workflows": ["rides-native-e2e.yml"], "unavailable": []})

    def test_home_services_has_no_native_e2e_and_says_so(self):
        r = plan("home-services", "consumer")
        self.assertEqual(r["workflows"], [])
        self.assertEqual(r["unavailable"], ["home-services/consumer"])

    def test_api_is_full_backend_ci(self):
        self.assertEqual(plan("home-services", "api")["workflows"], ["backend.yml"])

    def test_full_is_union_of_suites_plus_api(self):
        self.assertEqual(plan("groceries", "full")["workflows"],
                         ["backend.yml", "groceries-native-e2e.yml", "groceries-roles-native-e2e.yml"])

    def test_all_products_reports_missing_ones_but_runs_the_rest(self):
        r = plan("all", "consumer")
        self.assertIn("rides-native-e2e.yml", r["workflows"] + plan("taxi", "consumer")["workflows"])
        self.assertIn("food/consumer", r["unavailable"])
        self.assertNotIn("health/consumer", r["unavailable"])

    def test_unknown_values_are_rejected(self):
        for args in (("nope", "api"), ("taxi", "nope")):
            with self.assertRaises(ValueError):
                plan(*args)

    def test_every_planned_workflow_exists_and_is_callable(self):
        names = set()
        for suite in SUITES:
            names |= set(plan("all", suite)["workflows"])
        for name in names:
            text = (WORKFLOWS / name).read_text(encoding="utf-8")
            self.assertIn("workflow_call", text, name)
        product_e2e = (WORKFLOWS / "product-e2e.yml").read_text(encoding="utf-8")
        for name in names:
            self.assertIn("./.github/workflows/" + name, product_e2e, "product-e2e.yml does not call " + name)


if __name__ == "__main__":
    unittest.main()
