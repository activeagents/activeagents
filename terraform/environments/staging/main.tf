# Staging environment configuration for ActiveAgents

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
  environment = "staging"

  # Cloud Run configuration
  image         = var.image
  min_instances = 0  # Scale to zero for cost savings
  max_instances = 5
  cpu           = "1"
  memory        = "512Mi"

  # Database configuration (smaller for staging)
  database_tier = "db-f1-micro"

  # Access control
  allow_public_access   = var.allow_public_access
  authorized_domain     = var.authorized_domain
}
