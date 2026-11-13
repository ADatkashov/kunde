output "host" {
  description = "Direct (non-pooled) endpoint host; Flyway needs a session connection."
  value       = neon_project.this.database_host
}

output "database" {
  value = neon_project.this.database_name
}

output "username" {
  value = neon_project.this.database_user
}

output "password" {
  value     = neon_project.this.database_password
  sensitive = true
}

# TLS is mandatory and the server certificate AND host name are verified
# (pgjdbc verify-full uses the JVM default trust store). Never sslmode=disable.
output "jdbc_url" {
  value = "jdbc:postgresql://${neon_project.this.database_host}/${neon_project.this.database_name}?sslmode=verify-full"
}
