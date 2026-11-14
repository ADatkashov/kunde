# KUNDE DEV on free tiers: Render (backend) + Neon (PostgreSQL). Synthetic data only.
# Country/environment/provider live in the cell contract so another country or
# cloud is a new environment root plus an adapter, not a rewrite.
module "cell" {
  source = "../../modules/country-cell"

  country             = "kz"
  environment         = "dev"
  provider_id         = "render-neon"
  region              = "frankfurt/aws-eu-central-1"
  data_region_country = "de"
  data_classification = "synthetic"
  feature_flags = {
    consumer_identity = var.consumer_identity_enabled
  }
}

module "database" {
  source = "../../modules/neon"

  name      = var.neon_project_name
  region_id = "aws-eu-central-1"
  org_id    = var.neon_org_id
}

module "backend" {
  source = "../../modules/render"

  name     = var.render_service_name
  region   = "frankfurt"
  repo_url = var.repo_url
  branch   = var.branch

  db_url      = module.database.jdbc_url
  db_username = module.database.username
  db_password = module.database.password

  oidc_issuer_uri           = var.oidc_issuer_uri
  oidc_audience             = var.oidc_audience
  oidc_client_id            = var.oidc_client_id
  oidc_token_profile        = var.oidc_token_profile
  consumer_identity_enabled = tobool(module.cell.cell.app_env.CONSUMER_IDENTITY_ENABLED)
}
