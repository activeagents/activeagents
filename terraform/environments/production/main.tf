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
  # 2Gi: Rails + Puma + Solid Queue in one container peaks ~1.2GB at boot.
  # At 1Gi the container was OOM-killed on start (2026-08-27); staging has
  # always run 2Gi. Do not lower without moving Solid Queue out of Puma.
  memory        = "2Gi"

  # Database configuration (production-scale)
  database_tier = "db-custom-2-4096"  # 2 vCPUs, 4GB RAM
}
