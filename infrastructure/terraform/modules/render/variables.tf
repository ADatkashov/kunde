variable "name" {
  type = string
}

variable "plan" {
  description = "Only 'free' is permitted by this repository: paid plans need explicit owner approval and a code change."
  type        = string
  default     = "free"

  validation {
    condition     = var.plan == "free"
    error_message = "Only the free plan is allowed (no paid resources without explicit owner approval)."
  }
}

variable "region" {
  description = "Render region: frankfurt, ohio, oregon, singapore or virginia. Not Kazakhstan: DEV with synthetic data only."
  type        = string
  default     = "frankfurt"

  validation {
    condition     = contains(["frankfurt", "ohio", "oregon", "singapore", "virginia"], var.region)
    error_message = "Unsupported Render region."
  }
}

variable "repo_url" {
  type = string
}

variable "branch" {
  type    = string
  default = "main"
}

variable "auto_deploy" {
  description = "Redeploy on every commit to the branch. Off by default; deploys then happen on apply or by manual deploy."
  type        = bool
  default     = false
}

variable "db_url" {
  description = "JDBC URL; must enforce TLS."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("sslmode=(verify-full|verify-ca|require)", var.db_url))
    error_message = "db_url must enforce TLS (sslmode=verify-full, verify-ca or require)."
  }
}

variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "java_tool_options" {
  type    = string
  default = "-Xmx256m -XX:MaxMetaspaceSize=128m -XX:ReservedCodeCacheSize=64m -Xss512k -XX:+UseSerialGC -XX:TieredStopAtLevel=1"
}

variable "oidc_issuer_uri" {
  description = "Empty keeps protected endpoints fail-closed (503 AUTHENTICATION_NOT_CONFIGURED)."
  type        = string
  default     = ""
}

variable "oidc_audience" {
  type    = string
  default = ""
}

variable "cors_allowed_origins" {
  type    = string
  default = ""
}

variable "consumer_identity_enabled" {
  type    = bool
  default = false
}

variable "environment_name" {
  description = "Value of KUNDE_ENVIRONMENT. Anything other than dev/local/test makes the backend refuse DEV OTP at startup."
  type        = string
  default     = "production"
}

variable "auth_phone_enabled" {
  description = "Own phone-OTP authentication (ADR-015, amended 2026-11-14)."
  type        = bool
  default     = false
}

variable "auth_phone_secret" {
  description = "Root secret for JWT/OTP/refresh hashing, at least 32 characters. Supplied via TF_VAR_auth_phone_secret from a GitHub secret; never committed."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.auth_phone_secret == "" || length(var.auth_phone_secret) >= 32
    error_message = "auth_phone_secret must be empty (feature off) or at least 32 characters."
  }
}

variable "auth_dev_otp_enabled" {
  description = "Fixed test OTP 123456 for allowlisted synthetic numbers. Only valid when environment_name is dev."
  type        = bool
  default     = false

  validation {
    condition     = !var.auth_dev_otp_enabled || var.environment_name == "dev"
    error_message = "DEV OTP may only be enabled when environment_name is dev."
  }
}

variable "auth_dev_otp_allowed_phones" {
  description = "Comma-separated synthetic numbers (+7700000XXXX) allowed to use the DEV OTP."
  type        = string
  default     = ""
}
