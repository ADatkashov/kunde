import importlib.util
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("product_profile", ROOT / "scripts/dev/product_profile.py")
pp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pp)
REG = pp.load()
YML = (ROOT / "backend/app/src/main/resources/application.yml").read_text(encoding="utf-8")


class ProductProfileTest(unittest.TestCase):
    def test_home_services_profile_enables_only_its_chain(self):
        env = pp.profile("dev-home-services")
        on = {k for k, v in env.items() if v == "true"}
        self.assertEqual(on, {"HOME_SERVICES_ENABLED", "BOOKING_ENABLED", "BOOKING_SEED_DEMO", "PARTNER_OPS_SEED_DEMO",
                              "CONSUMER_IDENTITY_ENABLED", "AUTH_PHONE_ENABLED", "AUTH_DEV_OTP_ENABLED"})

    def test_other_products_are_disabled_explicitly_not_by_omission(self):
        env = pp.profile("dev-home-services")
        for flag in ("DELIVERY_ENABLED", "RIDES_ENABLED", "FOOD_ENABLED", "FLOWERS_ENABLED", "EDUCATION_ENABLED", "AUTO_ENABLED",
                     "LEISURE_ENABLED", "BEAUTY_ENABLED", "FOOD_SEED_DEMO", "HEALTH_SEED_DEMO", "DELIVERY_DISPATCH_ENABLED"):
            self.assertEqual(env[flag], "false", flag)

    def test_profiles_for_the_documented_products(self):
        self.assertEqual(pp.profile("dev-taxi")["RIDES_ENABLED"], "true")
        self.assertEqual(pp.profile("dev-taxi")["DELIVERY_ENABLED"], "false")
        self.assertEqual(pp.profile("dev-delivery")["DELIVERY_DISPATCH_ENABLED"], "true")
        self.assertEqual(pp.profile("dev-food")["FOOD_ENABLED"], "true")
        self.assertEqual(pp.profile("dev-food")["HOME_SERVICES_ENABLED"], "false")

    def test_dev_all_enables_every_product_flag(self):
        env = pp.profile("dev-all")
        self.assertTrue(all(v == "true" for v in env.values()))

    def test_every_product_has_a_profile_and_unknown_is_rejected(self):
        for product in REG["products"]:
            self.assertEqual(pp.profile("dev-" + product)[REG["products"][product]["profile_flags"][0]], "true")
        for bad in ("dev-nope", "home-services", ""):
            with self.assertRaises(ValueError):
                pp.profile(bad)

    def test_every_flag_exists_in_application_yml(self):
        for flag in pp.all_flags(REG) + REG["profile_always_on"]:
            self.assertRegex(YML, r"\$\{%s:" % re.escape(flag), flag + " is not a flag of application.yml")

    def test_education_defaults_to_true_so_the_profile_must_switch_it_off(self):
        self.assertIn("EDUCATION_ENABLED:true", YML)
        self.assertEqual(pp.profile("dev-home-services")["EDUCATION_ENABLED"], "false")


if __name__ == "__main__":
    unittest.main()
