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
    condition     = render_web_service.this.plan == "free" && render_web_service.this.health_check_path == "/actuator/health/liveness"
    error_message = "free plan and liveness probe required"
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

run "omits_empty_optional_env_vars" {
  command = plan
  assert {
    condition     = !contains(keys(render_web_service.this.env_vars), "OIDC_ISSUER_URI") && !contains(keys(render_web_service.this.env_vars), "CORS_ALLOWED_ORIGINS") && !contains(keys(render_web_service.this.env_vars), "OIDC_AUDIENCE")
    error_message = "empty optional env vars must not be sent"
  }
}

run "phone_auth_is_off_by_default" {
  command = plan
  assert {
    condition     = !contains(keys(render_web_service.this.env_vars), "AUTH_PHONE_ENABLED") && !contains(keys(render_web_service.this.env_vars), "AUTH_DEV_OTP_ENABLED") && render_web_service.this.env_vars["KUNDE_ENVIRONMENT"].value == "production"
    error_message = "phone auth and DEV OTP must be absent by default and the environment must default to production"
  }
}

run "rejects_dev_otp_outside_dev" {
  command = plan
  variables {
    auth_phone_enabled   = true
    auth_phone_secret    = "synthetic-test-secret-0123456789abcdef"
    auth_dev_otp_enabled = true
  }
  expect_failures = [var.auth_dev_otp_enabled]
}

run "rejects_short_phone_auth_secret" {
  command = plan
  variables { auth_phone_secret = "short" }
  expect_failures = [var.auth_phone_secret]
}

run "dev_otp_allowed_in_dev" {
  command = plan
  variables {
    environment_name            = "dev"
    auth_phone_enabled          = true
    auth_phone_secret           = "synthetic-test-secret-0123456789abcdef"
    auth_dev_otp_enabled        = true
    auth_dev_otp_allowed_phones = "+77000000001"
  }
  assert {
    condition     = render_web_service.this.env_vars["AUTH_DEV_OTP_ENABLED"].value == "true" && render_web_service.this.env_vars["KUNDE_ENVIRONMENT"].value == "dev"
    error_message = "DEV OTP env vars expected in dev"
  }
}
