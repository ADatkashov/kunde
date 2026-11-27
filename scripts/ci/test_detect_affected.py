import json
import pathlib
import subprocess
import tempfile
import unittest

import detect_affected as da

D = da.Detector()


def detect(*paths):
    return D.detect(list(paths))


def modes(result):
    return {app: cfg["mode"] for app, cfg in result["flutter"]["apps"].items()}


class PilotScenarios(unittest.TestCase):
    """ADR-027 Home Services pilot scenarios A-G, against the real repository graph."""

    def test_a_home_services_only(self):
        r = detect("backend/services/homeservices/src/main/java/kz/kunde/homeservices/HomeServicesSettings.java")
        self.assertEqual(r["scope"], "selective")
        self.assertEqual(r["products"]["affected"], ["home-services"])
        self.assertEqual(r["backend"]["gradle_tasks"], [":services:homeservices:test"])
        self.assertEqual(r["backend"]["app_test_packages"], ["homeservices"])
        # Feature isolation follows real imports: importers of home_services (booking, home, ...) are included, never fewer.
        self.assertTrue({"home", "home_services", "booking"} <= set(r["flutter"]["apps"]["consumer"]["features"]))
        self.assertEqual(r["flutter"]["apps"]["executor"]["features"], ["executor", "home_services"])
        self.assertIn("taxi", r["products"]["skipped"])
        self.assertIn("food", r["products"]["skipped"])

    def test_b_taxi_does_not_run_home_services(self):
        r = detect("backend/services/rides/src/main/java/kz/kunde/rides/A.java")
        self.assertEqual(r["products"]["affected"], ["taxi"])
        self.assertIn("home-services", r["products"]["skipped"])
        self.assertNotIn(":services:homeservices:test", r["backend"]["gradle_tasks"])
        self.assertNotIn("executor", r["flutter"]["apps"])  # no Taxi code in Executor
        self.assertEqual(r["flutter"]["apps"]["admin"]["features"], ["rides_admin"])

    def test_c_booking_runs_all_consumers_of_booking(self):
        r = detect("backend/services/booking/src/main/java/kz/kunde/booking/BookingService.java")
        self.assertEqual(set(r["products"]["affected"]), {"home-services", "beauty", "health", "auto"})
        for module in ("homeservices", "beauty", "health", "auto", "booking"):
            self.assertIn(":services:%s:test" % module, r["backend"]["gradle_tasks"])
        self.assertNotIn(":services:rides:test", r["backend"]["gradle_tasks"])
        self.assertIn("taxi", r["products"]["skipped"])

    def test_d_identity_reaches_everything(self):
        r = detect("backend/services/identity/src/main/java/kz/kunde/auth/A.java")
        self.assertEqual(set(r["products"]["affected"]), set(D.products))
        self.assertEqual(r["backend"]["app_tests"], "all")
        self.assertEqual(r["products"]["skipped"], {})

    def test_e_shared_flutter_package_runs_consumer_apps(self):
        r = detect("packages/kunde_ui/lib/src/button.dart")
        self.assertEqual(modes(r), {"consumer": "all", "executor": "all", "admin": "all"})  # partner does not depend on kunde_ui
        self.assertIn("kunde_ui", r["flutter"]["packages"])
        r = detect("packages/kunde_session/lib/a.dart")  # transitive: session -> auth -> api -> ui -> apps
        self.assertEqual(modes(r), {"consumer": "all", "executor": "all", "admin": "all", "partner": "all"})
        self.assertIn("kunde_api", r["flutter"]["packages"])

    def test_f_migration_runs_app_integration_tests(self):
        r = detect("backend/app/src/main/resources/db/migration/V77__x.sql")
        self.assertTrue(r["backend"]["migration"])
        self.assertEqual(r["backend"]["app_tests"], "all")
        self.assertEqual(r["scope"], "selective")

    def test_g_unknown_scope_is_full(self):
        for path in ("weird/file.txt", "backend/services/ghost/src/A.java", ".github/workflows/backend.yml",
                     "scripts/ci/detect_affected.py", "backend/gradle/libs.versions.toml", "backend/settings.gradle.kts", "compose.yaml"):
            r = detect(path)
            self.assertEqual(r["scope"], "full", path)
            self.assertTrue(r["full"] and r["reasons"], path)
            self.assertEqual(modes(r), dict.fromkeys(da.APPS, "all"))
            self.assertEqual(r["products"]["skipped"], {})

    def test_full_wins_over_selective(self):
        r = detect("backend/services/homeservices/src/A.java", "mystery.bin")
        self.assertEqual(r["scope"], "full")


class ClassificationDetails(unittest.TestCase):
    def test_docs_only(self):
        r = detect("docs/architecture/adr/ADR-027.md", "README.md")
        self.assertEqual(r["scope"], "docs")
        self.assertFalse(r["backend"]["run"] or r["flutter"]["run"])
        self.assertEqual(r["backend"]["app_tests"], "none")

    def test_flutter_feature_tests_only_run_that_feature(self):
        r = detect("apps/consumer/test/features/home_services/a_test.dart")
        self.assertEqual(modes(r), {"consumer": "selective"})
        self.assertEqual(r["flutter"]["apps"]["consumer"]["features"], ["home_services"])
        self.assertFalse(r["backend"]["run"])

    def test_shared_and_unregistered_feature_dirs_run_the_whole_app(self):
        self.assertEqual(modes(detect("apps/consumer/lib/features/shell/a.dart")), {"consumer": "all"})
        self.assertEqual(modes(detect("apps/consumer/lib/features/brand_new/a.dart")), {"consumer": "all"})
        self.assertEqual(modes(detect("apps/consumer/pubspec.lock")), {"consumer": "all"})
        self.assertEqual(modes(detect("apps/executor/lib/main.dart")), {"executor": "all"})

    def test_partner_has_flat_tests_so_it_runs_whole(self):
        self.assertEqual(modes(detect("apps/partner/lib/features/home_services/a.dart")), {"partner": "all"})

    def test_backend_change_pulls_in_feature_tests_of_its_clients(self):
        r = detect("backend/services/food/src/main/java/kz/kunde/food/A.java")
        self.assertIn("groceries", r["flutter"]["apps"]["consumer"]["features"])
        self.assertIn("food_admin", r["flutter"]["apps"]["admin"]["features"])
        self.assertIn("groceries", r["products"]["affected"])  # groceries depends on food

    def test_app_module_test_for_one_domain(self):
        r = detect("backend/app/src/test/java/kz/kunde/beauty/BeautyHttpTest.java")
        self.assertEqual(r["products"]["affected"], ["beauty"])
        self.assertEqual(r["backend"]["app_test_packages"], ["beauty"])
        r = detect("backend/app/src/test/java/kz/kunde/architecture/X.java")
        self.assertEqual(r["backend"]["app_tests"], "all")

    def test_dockerfile_and_infra_flags(self):
        self.assertTrue(detect("backend/Dockerfile")["backend"]["docker"])
        self.assertTrue(detect("infrastructure/terraform/a.tf")["infra"])

    def test_empty_change_runs_nothing(self):
        r = detect()
        self.assertEqual(r["scope"], "none")
        self.assertFalse(r["backend"]["run"] or r["flutter"]["run"])


class GraphAndFailSafe(unittest.TestCase):
    def test_every_gradle_module_is_registered(self):
        registered = set(D.shared) | set(D.module_product) | {"app"}
        self.assertEqual(registered, set(da.backend_graph()))

    def test_graph_is_read_from_gradle_and_pubspec(self):
        g = da.backend_graph()
        self.assertIn("booking", g["homeservices"])
        self.assertIn("platform", g["identity"])
        f = da.flutter_graph()
        self.assertIn("kunde_ui", f["consumer"])
        self.assertIn("kunde_auth", f["kunde_api"])

    def test_cycle_is_rejected(self):
        with self.assertRaises(da.GraphError):
            da.check_acyclic({"a": {"b"}, "b": {"a"}}, "test")

    def test_registry_drift_is_rejected(self):
        reg = da.load_registry()
        del reg["products"]["food"]
        with self.assertRaises(da.GraphError):
            da.Detector(registry=reg)

    def test_unusable_shas_fall_back_to_full(self):
        for base in ("", "0" * 40, "nonsense"):
            with self.assertRaises(ValueError):
                da.changed_paths(base, "a" * 40)
        self.assertTrue(da.full_fallback("x")["full"])

    def test_git_diff_reports_renames_deletes_and_adds(self):
        with tempfile.TemporaryDirectory() as tmp:
            def git(*a):
                return subprocess.check_output(["git", "-c", "user.name=t", "-c", "user.email=t@t", *a], cwd=tmp, text=True).strip()
            git("init", "-q")
            root = pathlib.Path(tmp)
            (root / "a.txt").write_text("keep\n" * 20)
            (root / "gone.txt").write_text("x\n")
            git("add", "."); git("commit", "-qm", "1")
            base = git("rev-parse", "HEAD")
            git("mv", "a.txt", "b.txt")
            git("rm", "-q", "gone.txt")
            (root / "new.txt").write_text("n\n")
            git("add", "."); git("commit", "-qm", "2")
            head = git("rev-parse", "HEAD")
            orig_root = da.ROOT
            da.ROOT = root
            try:
                paths = da.changed_paths(base, head)
            finally:
                da.ROOT = orig_root
            self.assertEqual(set(paths), {"a.txt", "b.txt", "gone.txt", "new.txt"})


if __name__ == "__main__":
    unittest.main()
