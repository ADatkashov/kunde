variable "repo_url" {
  description = "Public GitHub repository Render builds from."
  type        = string
  default     = "https://github.com/ADatkashov/kunde"
}

variable "neon_project_name" {
  type    = string
  default = "kunde-dev"
}

variable "render_service_name" {
  type    = string
  default = "kunde-backend"
}

variable "branch" {
  type    = string
  default = "main"
}

variable "neon_org_id" {
  description = "Neon organization id (org-...); required for organization-owned accounts. Set via TF_VAR_neon_org_id (GitHub variable), not committed."
  type        = string
  default     = null
}

variable "oidc_issuer_uri" {
  type    = string
  default = ""
}

variable "oidc_audience" {
  type    = string
  default = ""
}

# Own phone-OTP authentication (ADR-015 amended 2026-11-14). Strings because they arrive as TF_VAR_* from
# GitHub variables/secrets; the workflow defaults them to "false"/"".
variable "auth_phone_enabled" {
  type    = string
  default = "false"

  validation {
    condition     = contains(["true", "false"], var.auth_phone_enabled)
    error_message = "auth_phone_enabled must be \"true\" or \"false\"."
  }
}

variable "auth_phone_secret" {
  description = "At least 32 characters; GitHub secret AUTH_PHONE_SECRET via TF_VAR_auth_phone_secret."
  type        = string
  default     = ""
  sensitive   = true
}

variable "auth_dev_otp_enabled" {
  type    = string
  default = "false"

  validation {
    condition     = contains(["true", "false"], var.auth_dev_otp_enabled)
    error_message = "auth_dev_otp_enabled must be \"true\" or \"false\"."
  }
}

variable "auth_dev_otp_allowed_phones" {
  description = "Synthetic numbers +7700000XXXX only."
  type        = string
  default     = "+77000000001,+77000000002,+77000000003"
}
