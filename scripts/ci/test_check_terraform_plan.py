import unittest
from check_terraform_plan import check


def rc(rtype, after, actions=("create",)):
    return {"address": f"{rtype}.x", "type": rtype, "change": {"actions": list(actions), "after": after}}


class PlanGate(unittest.TestCase):
    def test_free_plan_passes(self):
        plan = {"resource_changes": [rc("render_web_service", {"plan": "free", "num_instances": 1}), rc("neon_project", {"history_retention_seconds": 21600}), rc("terraform_data", {})]}
        self.assertEqual(check(plan), [])

    def test_paid_plan_disk_and_scaling_rejected(self):
        self.assertTrue(check({"resource_changes": [rc("render_web_service", {"plan": "starter"})]}))
        self.assertTrue(check({"resource_changes": [rc("render_web_service", {"plan": "free", "disk": {"size_gb": 1}})]}))
        self.assertTrue(check({"resource_changes": [rc("render_web_service", {"plan": "free", "num_instances": 2})]}))

    def test_delete_and_replace_rejected(self):
        self.assertTrue(check({"resource_changes": [rc("neon_project", {}, ("delete",))]}))
        self.assertTrue(check({"resource_changes": [rc("neon_project", {}, ("delete", "create"))]}))

    def test_render_replace_only_when_explicitly_allowed(self):
        plan = {"resource_changes": [rc("render_web_service", {"plan": "free"}, ("delete", "create"))]}
        self.assertTrue(check(plan))
        self.assertEqual(check(plan, allow_render_replace=True), [])

    def test_replace_allowance_never_covers_other_deletes(self):
        self.assertTrue(check({"resource_changes": [rc("neon_project", {}, ("delete", "create"))]}, allow_render_replace=True))
        self.assertTrue(check({"resource_changes": [rc("render_web_service", {"plan": "free"}, ("delete",))]}, allow_render_replace=True))

    def test_unknown_resource_type_rejected(self):
        self.assertTrue(check({"resource_changes": [rc("render_postgres", {})]}))

    def test_neon_paid_features_rejected(self):
        self.assertTrue(check({"resource_changes": [rc("neon_project", {"history_retention_seconds": 86400})]}))
        self.assertTrue(check({"resource_changes": [rc("neon_project", {"hipaa": True})]}))

    def test_sensitive_output_rejected(self):
        self.assertTrue(check({"planned_values": {"outputs": {"pw": {"sensitive": True}}}}))


if __name__ == "__main__":
    unittest.main()
