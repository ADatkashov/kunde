variable "name" {
  type = string
}

variable "region_id" {
  description = "Neon region id, e.g. aws-eu-central-1. Neon has no Kazakhstan region: DEV with synthetic data only."
  type        = string
  default     = "aws-eu-central-1"
}

variable "pg_version" {
  description = "Matches CI and compose.yaml (PostgreSQL 16)."
  type        = number
  default     = 16
}

variable "org_id" {
  description = "Neon organization id; required by the API for organization-owned accounts, null for personal accounts."
  type        = string
  default     = null
}

variable "database_name" {
  type    = string
  default = "kunde"
}

variable "role_name" {
  type    = string
  default = "kunde_owner"
}
