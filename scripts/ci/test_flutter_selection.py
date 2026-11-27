import unittest

import detect_affected as da
from flutter_selection import selection

D = da.Detector()


def sel(app, *paths):
    return selection(D.detect(list(paths)), app)


class FlutterSelectionTest(unittest.TestCase):
    def test_full_runs_everything(self):
        r = sel("executor", "mystery.bin")
        self.assertEqual(r["mode"], "all")
        self.assertIn("kunde_ui", r["packages"])

    def test_unreached_app_is_skipped(self):
        self.assertEqual(sel("executor", "apps/consumer/lib/features/rides/a.dart")["mode"], "skip")
        self.assertEqual(sel("admin", "apps/executor/lib/features/home_services/a.dart")["mode"], "skip")

    def test_executor_feature_runs_only_existing_feature_tests(self):
        r = sel("executor", "apps/executor/lib/features/home_services/a.dart")
        self.assertEqual(r["mode"], "selective")
        self.assertIn("test/features/home_services", r["tests"])
        self.assertNotIn("test/features/leisure", r["tests"])
        self.assertEqual(r["packages"], [])

    def test_importers_of_a_changed_feature_are_retested(self):
        r = sel("admin", "apps/admin/lib/features/home_services_admin/a.dart")
        self.assertIn("test/features/home_services_admin", r["tests"])
        self.assertIn("test/features/rides_admin", r["tests"])  # rides_admin imports home_services_admin

    def test_consumer_transitive_feature_edges_are_followed(self):
        # booking imports home_services, home imports booking: a taxi (rides) change reaches home_services tests through that chain
        r = sel("consumer", "apps/consumer/lib/features/rides/a.dart")
        self.assertIn("test/features/rides", r["tests"])
        self.assertIn("test/features/home", r["tests"])
        self.assertIn("test/features/home_services", r["tests"])

    def test_package_change_runs_whole_app_and_that_package(self):
        r = sel("consumer", "packages/kunde_maps/lib/a.dart")
        self.assertEqual(r["mode"], "all")
        self.assertEqual(r["packages"], ["kunde_maps"])
        self.assertEqual(sel("admin", "packages/kunde_maps/lib/a.dart")["mode"], "skip")  # admin does not use kunde_maps

    def test_feature_graph_matches_known_imports(self):
        g = D.features
        self.assertIn("booking", g["consumer"]["home_services"])
        self.assertIn("home_services", g["executor"]["executor"])


if __name__ == "__main__":
    unittest.main()
