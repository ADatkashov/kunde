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

  # Liveness, not readiness: readiness queries the DB every few seconds and would keep Neon awake
  # (free plan: 100 CU-hours/month). Flyway failure still aborts startup, so a live app has migrated.
  health_check_path = "/actuator/health/liveness"
  # max_shutdown_delay_seconds is not supported on the free plan (Render API rejects it);
  # the app still shuts down gracefully within spring.lifecycle.timeout-per-shutdown-phase (20 s).

  runtime_source = {
    docker = {
      repo_url            = var.repo_url
      branch              = var.branch
      dockerfile_path     = "./backend/Dockerfile"
      context             = "./backend"
      auto_deploy_trigger = var.auto_deploy ? "commit" : "off"
    }
  }

  # Empty values are omitted: Render drops them and the provider reports an inconsistent result;
  # the backend defaults them to empty (application.yml: ${OIDC_ISSUER_URI:} etc.).
  env_vars = merge(
    {
      PORT        = { value = "8080" }
      DB_URL      = { value = var.db_url }
      DB_USERNAME = { value = var.db_username }
      DB_PASSWORD = { value = var.db_password }
      # Neon free has a small connection budget; keep the pool small.
      DB_POOL_SIZE = { value = "5" }
      # Close idle connections so the Neon compute can autosuspend; tolerate a cold-start resume.
      SPRING_DATASOURCE_HIKARI_MINIMUMIDLE       = { value = "0" }
      SPRING_DATASOURCE_HIKARI_IDLETIMEOUT       = { value = "30000" }
      SPRING_DATASOURCE_HIKARI_CONNECTIONTIMEOUT = { value = "10000" }
      # Keep the JVM inside 512 MB: explicit -Xmx wins over the image's
      # MaxRAMPercentage=75, so backend/Dockerfile stays unchanged.
      JAVA_TOOL_OPTIONS         = { value = var.java_tool_options }
      CONSUMER_IDENTITY_ENABLED = { value = tostring(var.consumer_identity_enabled) }
    },
    var.oidc_issuer_uri == "" ? {} : { OIDC_ISSUER_URI = { value = var.oidc_issuer_uri } },
    var.oidc_audience == "" ? {} : { OIDC_AUDIENCE = { value = var.oidc_audience } },
    var.oidc_client_id == "" ? {} : { CONSUMER_CLIENT_ID = { value = var.oidc_client_id } },
    var.oidc_token_profile == "keycloak" ? {} : { OIDC_TOKEN_PROFILE = { value = var.oidc_token_profile } },
    var.cors_allowed_origins == "" ? {} : { CORS_ALLOWED_ORIGINS = { value = var.cors_allowed_origins } },
  )
}
