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

# TLS is mandatory and both the server certificate chain and the host name are verified.
# pgjdbc's verify-full reads ~/.postgresql/root.crt by default (the first Render deploy
# failed on exactly that); DefaultJavaSSLFactory makes it use the JVM trust store instead.
# Verified locally: trusted cert + matching host starts, untrusted cert and host-name
# mismatch are both rejected. Never sslmode=disable/require.
output "jdbc_url" {
  value = "jdbc:postgresql://${neon_project.this.database_host}/${neon_project.this.database_name}?sslmode=verify-full&sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory"
}
