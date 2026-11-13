terraform {
  required_version = ">= 1.10.0" # S3 native state locking (use_lockfile)

  # Partial configuration: bucket, key, endpoint and credentials come from
  # -backend-config / environment, never from Git. See backend.hcl.example.
  backend "s3" {}

  required_providers {
    render = {
      source  = "render-oss/render"
      version = "1.9.1"
    }
    neon = {
      source  = "kislerdm/neon"
      version = "0.18.0"
    }
  }
}

# Credentials only via environment: RENDER_API_KEY, RENDER_OWNER_ID, NEON_API_KEY.
provider "render" {}
provider "neon" {}
