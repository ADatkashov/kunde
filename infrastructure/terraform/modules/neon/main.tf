terraform {
  required_version = ">= 1.9.0"
  required_providers {
    neon = {
      source  = "kislerdm/neon"
      version = "0.18.0"
    }
  }
}

# Free-tier Neon project with the default branch, role and database that the
# project resource creates. No paid features (extra computes, IP allow-list,
# private networking, HIPAA) are configured. Synthetic DEV data only.
resource "neon_project" "this" {
  name       = var.name
  region_id  = var.region_id
  pg_version = var.pg_version
  org_id     = var.org_id

  # Free plan caps point-in-time history at 6 h (21600 s); the provider default (1 day) is a paid feature.
  history_retention_seconds = 21600

  branch {
    name          = "main"
    database_name = var.database_name
    role_name     = var.role_name
  }
}
