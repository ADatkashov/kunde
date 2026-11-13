variable "country" {
  description = "ISO 3166-1 alpha-2 country code, lowercase (cell identity)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}$", var.country))
    error_message = "country must be a two-letter lowercase ISO 3166-1 code."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "provider_id" {
  description = "Provider adapter id. 'unselected' is the only value until a provider passes the procurement gate (TASK-051)."
  type        = string
  default     = "unselected"

  validation {
    condition     = contains(["unselected", "local-compose", "render-neon"], var.provider_id)
    error_message = "Only providers with a verified adapter may be named; add the adapter and update this list in the same reviewed change."
  }
}

variable "region" {
  description = "Provider region id inside the country; empty while the provider is unselected."
  type        = string
  default     = ""
}

variable "data_region_country" {
  description = "Country in which the primary database, backups and telemetry are stored. Must equal var.country for personal data (ADR-012)."
  type        = string
}

variable "data_classification" {
  description = "'personal' (real user data: residency enforced) or 'synthetic' (fake data only; allowed outside prod)."
  type        = string
  default     = "personal"

  validation {
    condition     = contains(["personal", "synthetic"], var.data_classification)
    error_message = "data_classification must be personal or synthetic."
  }
}

variable "cross_border_replication" {
  description = "Must stay false: no automatic cross-border replication of personal data (ADR-012)."
  type        = bool
  default     = false

  validation {
    condition     = var.cross_border_replication == false
    error_message = "Cross-border replication of personal data is forbidden without counsel approval and a new ADR."
  }
}

variable "runtime" {
  description = "Runtime shape: 'container-service' (managed compute, default) or 'kubernetes' (only when scale justifies it, ADR-011)."
  type        = string
  default     = "container-service"

  validation {
    condition     = contains(["container-service", "kubernetes"], var.runtime)
    error_message = "runtime must be container-service or kubernetes."
  }
}

variable "feature_flags" {
  description = "Non-secret runtime flags the backend already reads (application.yml). The marketplace stays disabled in code (ADR-014); no flag is invented here."
  type = object({
    consumer_identity = bool
  })
  default = {
    consumer_identity = false
  }
}

variable "secret_names" {
  description = "Names (never values) of secrets the cell must inject at runtime."
  type        = list(string)
  default     = ["DB_URL", "DB_USERNAME", "DB_PASSWORD", "OIDC_ISSUER_URI", "OIDC_AUDIENCE"]
}
