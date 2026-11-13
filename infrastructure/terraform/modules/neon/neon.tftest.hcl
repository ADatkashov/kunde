mock_provider "neon" {
  mock_resource "neon_project" {
    defaults = {
      database_host     = "ep-test.eu-central-1.aws.neon.tech"
      database_name     = "kunde"
      database_user     = "kunde_owner"
      database_password = "mock-password"
    }
  }
}

variables {
  name = "kunde-dev"
}

run "tls_verified_jdbc_url_without_credentials" {
  command = apply
  assert {
    condition     = output.jdbc_url == "jdbc:postgresql://ep-test.eu-central-1.aws.neon.tech/kunde?sslmode=verify-full"
    error_message = "JDBC URL must verify the server certificate and host name"
  }
  assert {
    condition     = !strcontains(output.jdbc_url, "mock-password") && !strcontains(output.jdbc_url, "@")
    error_message = "JDBC URL must not embed credentials"
  }
}
