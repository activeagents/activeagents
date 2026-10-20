# Production environment configuration for ActiveAgents

terraform {
  required_version = ">= 1.5.0"
  # Backend configured in backend.tf
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

module "activeagents" {
  source = "../../"

  project_id  = var.project_id
  region      = var.region
  environment = "production"

  # Cloud Run configuration (production-scale)
  image         = var.image
  min_instances = 1 # Always keep at least 1 instance warm
  max_instances = 20
  cpu           = "2"
  memory        = "1Gi"

  # Checkout sandboxes on the Incus host stay off until its egress controls
  # (https://github.com/activeagents/activeagents/issues/150) are applied.
  incus_app_runtime_enabled = false

  # Production has no Incus host of its own yet. Claude Code sign-in in
  # sandboxes keeps its defaults (api_key, hosted login off).
  enable_incus_backend = false

  # Database configuration (production-scale)
  database_tier = "db-custom-2-4096" # 2 vCPUs, 4GB RAM

  # Public signup protection: Cloud Armor in front of the load balancer and
  # Cloudflare Turnstile on the forms (docs/features/human-check.md).
  enable_security_policy = var.enable_security_policy
  blocked_source_ranges  = var.blocked_source_ranges
  signup_rate_limit      = var.signup_rate_limit
  enable_turnstile       = var.enable_turnstile
  turnstile_site_key     = var.turnstile_site_key

  # Sign in with GitHub, through this environment's GitHub App, and Sign in
  # with Google, through its OAuth client
  enable_github_sign_in = var.enable_github_sign_in
  enable_google_sign_in = var.enable_google_sign_in

  # GitHub App repository access, encryption keys and recordings storage.
  # Each flag stays off until docs/infrastructure/gcp-cicd-setup.md says to
  # turn it on.
  enable_github_app                    = var.enable_github_app
  github_app_id                        = var.github_app_id
  github_app_slug                      = var.github_app_slug
  enable_active_record_encryption_keys = var.enable_active_record_encryption_keys
  enable_recordings_storage            = var.enable_recordings_storage
}
