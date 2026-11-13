mock_provider "render" {}

variables {
  name        = "kunde-dev"
  repo_url    = "https://github.com/example/kunde"
  db_url      = "jdbc:postgresql://h/db?sslmode=verify-full"
  db_username = "u"
  db_password = "p"
}

run "free_plan_and_probe" {
  command = plan
  assert {
    condition     = render_web_service.this.plan == "free" && render_web_service.this.health_check_path == "/actuator/health/readiness"
    error_message = "free plan and readiness probe required"
  }
  assert {
    condition     = render_web_service.this.runtime_source.docker.dockerfile_path == "./backend/Dockerfile"
    error_message = "must reuse the existing backend Dockerfile"
  }
}

run "rejects_paid_plan" {
  command = plan
  variables { plan = "starter" }
  expect_failures = [var.plan]
}

run "rejects_cleartext_database_url" {
  command = plan
  variables { db_url = "jdbc:postgresql://h/db?sslmode=disable" }
  expect_failures = [var.db_url]
}

run "rejects_unknown_region" {
  command = plan
  variables { region = "kazakhstan" }
  expect_failures = [var.region]
}
