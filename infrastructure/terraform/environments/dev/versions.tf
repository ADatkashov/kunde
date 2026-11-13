terraform {
  required_version = ">= 1.9.0"

  # HCP Terraform (free) holds the state: encrypted, versioned, locked during runs.
  # Organization, workspace and token come from the environment, never from Git:
  # TF_CLOUD_ORGANIZATION, TF_WORKSPACE, TF_TOKEN_app_terraform_io.
  # The workspace must use Local execution mode (runs happen in GitHub Actions).
  cloud {}

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
