variables {
  country             = "kz"
  environment         = "dev"
  data_region_country = "kz"
}

run "valid_unselected_provider" {
  command = apply
  assert {
    condition     = output.cell.id == "kz-dev" && output.cell.database_name == "kunde_kz_dev"
    error_message = "cell id/database name must derive from country and environment"
  }
  assert {
    condition     = output.cell.app_env.CONSUMER_IDENTITY_ENABLED == "false"
    error_message = "consumer identity must default to disabled"
  }
}

run "rejects_cross_border_replication" {
  command = plan
  variables { cross_border_replication = true }
  expect_failures = [var.cross_border_replication]
}

run "rejects_foreign_data_region" {
  command = plan
  variables { data_region_country = "uz" }
  expect_failures = [terraform_data.contract]
}

run "rejects_unverified_provider" {
  command = plan
  variables {
    provider_id = "aws"
    region      = "eu-west-1"
  }
  expect_failures = [var.provider_id]
}

run "rejects_region_without_provider" {
  command = plan
  variables { region = "x" }
  expect_failures = [terraform_data.contract]
}

run "rejects_secret_values" {
  command = plan
  variables { secret_names = ["db-password=hunter2"] }
  expect_failures = [terraform_data.contract]
}

run "rejects_prod_on_local_runtime" {
  command = plan
  variables {
    environment = "prod"
    provider_id = "local-compose"
    region      = "local"
  }
  expect_failures = [terraform_data.contract]
}
