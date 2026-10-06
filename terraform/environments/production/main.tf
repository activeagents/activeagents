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
  min_instances = 1  # Always keep at least 1 instance warm
  max_instances = 20
  cpu           = "2"
  memory        = "1Gi"

  # Database configuration (production-scale)
  database_tier = "db-custom-2-4096"  # 2 vCPUs, 4GB RAM

  # Sign in with GitHub, through this environment's GitHub App
  enable_github_sign_in = var.enable_github_sign_in

  # GitHub App repository access, encryption keys and recordings storage.
  # Each flag stays off until docs/infrastructure/gcp-cicd-setup.md says to
  # turn it on.
  enable_github_app                    = var.enable_github_app
  github_app_id                        = var.github_app_id
  github_app_slug                      = var.github_app_slug
  enable_active_record_encryption_keys = var.enable_active_record_encryption_keys
  enable_recordings_storage            = var.enable_recordings_storage
}
