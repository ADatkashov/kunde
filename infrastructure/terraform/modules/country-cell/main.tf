terraform {
  required_version = ">= 1.9.0"
}

# Provider-neutral contract only. It creates no cloud resources: provider
# adapters (infrastructure/providers/<id>) consume `cell` once a provider is
# verified. Everything below is validation and normalisation.
locals {
  cell_id = "${var.country}-${var.environment}"

  residency_ok = var.data_classification == "synthetic" || var.data_region_country == var.country
  synthetic_ok = var.data_classification == "personal" || var.environment != "prod"
  provider_ok  = var.provider_id == "unselected" ? var.region == "" : var.region != ""
  prod_ok      = var.environment != "prod" || !contains(["local-compose", "render-neon"], var.provider_id)

  secret_names_ok = alltrue([for n in var.secret_names : can(regex("^[A-Z][A-Z0-9_]*$", n))])

  cell = {
    id                  = local.cell_id
    country             = var.country
    environment         = var.environment
    provider_id         = var.provider_id
    region              = var.region
    data_region         = var.data_region_country
    runtime             = var.runtime
    database_name       = "kunde_${var.country}_${var.environment}"
    secret_names        = var.secret_names
    data_classification = var.data_classification
    app_env = {
      CONSUMER_IDENTITY_ENABLED = tostring(var.feature_flags.consumer_identity)
    }
  }
}

resource "terraform_data" "contract" {
  input = local.cell

  lifecycle {
    precondition {
      condition     = local.residency_ok
      error_message = "Residency: data_region_country must equal country (ADR-012)."
    }
    precondition {
      condition     = local.synthetic_ok
      error_message = "Synthetic data classification is not allowed in prod."
    }
    precondition {
      condition     = local.provider_ok
      error_message = "region must be empty for an unselected provider and set otherwise."
    }
    precondition {
      condition     = local.prod_ok
      error_message = "local-compose and render-neon (free tiers, no verified residency) are not production runtimes."
    }
    precondition {
      condition     = local.secret_names_ok
      error_message = "secret_names must be UPPER_SNAKE_CASE names, not values."
    }
  }
}
