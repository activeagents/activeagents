# ActiveAgents Infrastructure
# This is the root module that orchestrates all infrastructure components

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # Backend configuration - will be configured per environment
  # See environments/staging/backend.tf and environments/production/backend.tf
}

# Local variables computed from inputs
locals {
  # Common labels applied to all resources
  common_labels = {
    project     = "activeagents"
    environment = var.environment
    managed_by  = "terraform"
  }

  # Service account email for Cloud Run
  cloud_run_sa_email = google_service_account.cloud_run.email
}

# Enable required GCP APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
    "vpcaccess.googleapis.com",
    "servicenetworking.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudtasks.googleapis.com",
    "pubsub.googleapis.com",
    "dns.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Service account for Cloud Run
resource "google_service_account" "cloud_run" {
  project      = var.project_id
  account_id   = "activeagents-${var.environment}"
  display_name = "ActiveAgents Cloud Run Service Account (${var.environment})"

  depends_on = [google_project_service.apis]
}

# Grant Cloud Run service account access to Secret Manager
resource "google_project_iam_member" "cloud_run_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# Grant Cloud Run service account access to Cloud SQL
resource "google_project_iam_member" "cloud_run_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# Artifact Registry for Docker images
resource "google_artifact_registry_repository" "activeagents" {
  project       = var.project_id
  location      = var.region
  repository_id = "activeagents"
  description   = "Docker repository for ActiveAgents"
  format        = "DOCKER"

  labels = local.common_labels

  depends_on = [google_project_service.apis]
}

# VPC Network for private connectivity
module "networking" {
  source = "./modules/networking"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  depends_on = [google_project_service.apis]
}

# Cloud SQL PostgreSQL instance
module "cloud_sql" {
  source = "./modules/cloud-sql"

  project_id   = var.project_id
  region       = var.region
  environment  = var.environment
  network_id   = module.networking.vpc_id
  network_name = module.networking.vpc_name

  database_name     = "activeagents_${var.environment}"
  database_user     = "activeagents"
  database_tier     = var.database_tier
  database_version  = "POSTGRES_15"

  labels = local.common_labels

  depends_on = [module.networking]
}

# Secret Manager secrets
module "secrets" {
  source = "./modules/secret-manager"

  project_id  = var.project_id
  environment = var.environment

  secrets = {
    rails-master-key = {
      description = "Rails master key for credentials encryption"
    }
    database-url = {
      description = "PostgreSQL connection URL"
    }
    stripe-api-key = {
      description = "Stripe API key for payment processing"
    }
    stripe-webhook-secret = {
      description = "Stripe webhook signing secret"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.apis]
}

# Cloud Run service
module "cloud_run" {
  source = "./modules/cloud-run"

  project_id         = var.project_id
  region             = var.region
  environment        = var.environment
  service_account    = google_service_account.cloud_run.email
  vpc_connector_id   = module.networking.vpc_connector_id

  image              = var.image
  min_instances      = var.min_instances
  max_instances      = var.max_instances
  cpu                = var.cpu
  memory             = var.memory

  cloud_sql_connection = module.cloud_sql.connection_name

  env_vars = {
    RAILS_ENV              = "production"
    RAILS_LOG_TO_STDOUT    = "true"
    RAILS_SERVE_STATIC_FILES = "true"
    SOLID_QUEUE_IN_PUMA    = "true"
    DB_HOST                = "/cloudsql/${module.cloud_sql.connection_name}"
    DB_NAME                = module.cloud_sql.database_name
    DB_USER                = module.cloud_sql.database_user
  }

  secret_env_vars = {
    RAILS_MASTER_KEY       = module.secrets.secret_ids["rails-master-key"]
    DB_PASSWORD            = module.cloud_sql.password_secret_id
    STRIPE_API_KEY         = module.secrets.secret_ids["stripe-api-key"]
    STRIPE_WEBHOOK_SECRET  = module.secrets.secret_ids["stripe-webhook-secret"]
  }

  labels = local.common_labels

  # Set to false if GCP org policy restricts public access
  allow_public_access = var.allow_public_access

  # Domain to grant access when public access is blocked
  authorized_domain = var.authorized_domain

  # CI service account for health checks
  ci_service_account = var.ci_service_account

  depends_on = [
    module.cloud_sql,
    module.secrets,
    module.networking,
    google_project_iam_member.cloud_run_secret_accessor,
    google_project_iam_member.cloud_run_cloudsql_client,
  ]
}

# Load Balancer for public access (bypasses org policy restrictions)
# NOTE: IAP is configured manually via gcloud (see modules/load-balancer/main.tf)
module "load_balancer" {
  count  = var.enable_load_balancer ? 1 : 0
  source = "./modules/load-balancer"

  project_id             = var.project_id
  region                 = var.region
  name                   = "activeagents-${var.environment}"
  cloud_run_service_name = module.cloud_run.service_name
  domain                 = var.lb_domain
  enable_cdn             = var.enable_cdn
  enable_http_redirect   = true

  depends_on = [
    module.cloud_run,
    google_project_service.apis,
  ]
}

# Sandbox infrastructure for dynamic agent execution environments
# Similar to HuggingFace Spaces or Google Colab
module "sandbox" {
  source = "./modules/sandbox"

  project_id          = var.project_id
  region              = var.region
  environment         = var.environment
  vpc_connector_id    = module.networking.vpc_connector_id
  app_service_account = google_service_account.cloud_run.email

  # Sandbox resource configuration
  default_sandbox_image     = var.sandbox_image
  sandbox_cpu               = var.sandbox_cpu
  sandbox_memory            = var.sandbox_memory
  sandbox_timeout_seconds   = var.sandbox_timeout_seconds
  max_concurrent_sandboxes  = var.max_concurrent_sandboxes
  max_persistent_sandboxes  = var.max_persistent_sandboxes

  labels = local.common_labels

  depends_on = [
    module.networking,
    google_project_service.apis,
  ]
}

# DNS configuration for activeagents.ai
module "dns" {
  count  = var.enable_dns ? 1 : 0
  source = "./modules/dns"

  project_id = var.project_id
  domain     = var.dns_domain

  # Point staging subdomain to the load balancer IP
  staging_ip = var.enable_load_balancer && var.environment == "staging" ? module.load_balancer[0].ip_address : null

  # Production IP (for future use)
  production_ip = var.enable_load_balancer && var.environment == "production" ? module.load_balancer[0].ip_address : null

  # Keep main site on Framer during migration
  framer_ips       = var.framer_ips
  framer_www_cname = var.framer_www_cname

  # Email and verification records
  mx_records             = var.mx_records
  txt_records            = var.txt_records
  dmarc_record           = var.dmarc_record
  additional_txt_records = var.additional_txt_records

  # Docs subdomain (GitHub Pages)
  docs_cname = var.docs_cname

  labels = local.common_labels

  depends_on = [
    google_project_service.apis,
    module.load_balancer,
  ]
}
