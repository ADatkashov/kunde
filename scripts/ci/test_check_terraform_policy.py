import unittest
from check_terraform_policy import check


class TerraformPolicy(unittest.TestCase):
    def test_clean_files_pass(self):
        self.assertEqual(check([("infrastructure/terraform/a.tf", 'url = "jdbc:postgresql://h/d?sslmode=verify-full"')]), [])

    def test_state_and_tfvars_rejected(self):
        self.assertEqual(len(check([("x/terraform.tfstate", ""), ("x/dev.tfvars", "")])), 2)

    def test_weak_tls_rejected(self):
        self.assertTrue(check([("infrastructure/terraform/a.tf", "?sslmode=disable")]))

    def test_embedded_credentials_rejected(self):
        self.assertTrue(check([("infrastructure/terraform/a.tf", "postgresql://u:pw@host/db")]))

    def test_literal_credential_rejected_but_reference_allowed(self):
        self.assertTrue(check([("infrastructure/terraform/a.tf", 'password = "hunter2"')]))
        self.assertEqual(check([("infrastructure/terraform/a.tf", 'password = var.pw')]), [])

    def test_auto_approve_only_in_apply_workflow(self):
        self.assertTrue(check([("infrastructure/terraform/a.sh", "terraform apply -auto-approve")]))
        self.assertEqual(check([(".github/workflows/terraform-dev.yml", "terraform apply -auto-approve tfplan")]), [])

    def test_comments_ignored_and_tftest_may_name_weak_tls(self):
        self.assertEqual(check([("infrastructure/terraform/a.tf", "# never sslmode=disable")]), [])
        self.assertEqual(check([("infrastructure/terraform/a.tftest.hcl", 'db_url = "x?sslmode=disable"')]), [])
        self.assertTrue(check([("infrastructure/terraform/a.tf", 'u = "x?sslmode=disable"')]))

    def test_destroy_rejected_in_workflows(self):
        self.assertTrue(check([(".github/workflows/terraform-dev.yml", "terraform destroy")]))


if __name__ == "__main__":
    unittest.main()
