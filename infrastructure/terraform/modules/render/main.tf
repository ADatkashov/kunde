terraform {
  required_version = ">= 1.9.0"
  required_providers {
    render = {
      source  = "render-oss/render"
      version = "1.9.1"
    }
  }
}

# One Docker web service built from the repository's existing backend/Dockerfile.
# Free plan: 512 MB RAM, 0.1 CPU, spins down after ~15 min idle (cold start
# about a minute). Free services cannot have disks, scaling or pre-deploy hooks.
resource "render_web_service" "this" {
  name   = var.name
  plan   = var.plan
  region = var.region

  health_check_path          = "/actuator/health/readiness"
  max_shutdown_delay_seconds = 30

  runtime_source = {
    docker = {
      repo_url            = var.repo_url
      branch              = var.branch
      dockerfile_path     = "./backend/Dockerfile"
      context             = "./backend"
      auto_deploy_trigger = var.auto_deploy ? "commit" : "off"
    }
  }

  env_vars = {
    PORT        = { value = "8080" }
    DB_URL      = { value = var.db_url }
    DB_USERNAME = { value = var.db_username }
    DB_PASSWORD = { value = var.db_password }
    # Neon free has a small connection budget; keep the pool small.
    DB_POOL_SIZE = { value = "5" }
    # Keep the JVM inside 512 MB: explicit -Xmx wins over the image's
    # MaxRAMPercentage=75, so backend/Dockerfile stays unchanged.
    JAVA_TOOL_OPTIONS         = { value = var.java_tool_options }
    OIDC_ISSUER_URI           = { value = var.oidc_issuer_uri }
    OIDC_AUDIENCE             = { value = var.oidc_audience }
    CORS_ALLOWED_ORIGINS      = { value = var.cors_allowed_origins }
    CONSUMER_IDENTITY_ENABLED = { value = tostring(var.consumer_identity_enabled) }
  }
}
