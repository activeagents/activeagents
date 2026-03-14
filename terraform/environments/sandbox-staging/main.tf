# Sandbox Staging Environment
#
# Standalone environment for testing Incus-based sandbox orchestration.
# Separate from the main production infrastructure.
#
# Deploy:
#   cd terraform/environments/sandbox-staging
#   terraform init
#   terraform plan
#   terraform apply

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Backend configuration - update for your setup
  backend "gcs" {
    bucket = "activeagents-terraform-state"
    prefix = "sandbox-staging"
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "activeagents-staging"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

provider "google" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------------------------
# Enable Required APIs
# -----------------------------------------------------------------------------

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

resource "google_compute_network" "sandbox" {
  name                    = "sandbox-network"
  auto_create_subnetworks = false
  project                 = var.project_id

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "sandbox" {
  name          = "sandbox-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.sandbox.id
  project       = var.project_id

  # For VPC connector (Cloud Run -> Incus)
  secondary_ip_range {
    range_name    = "serverless-connector"
    ip_cidr_range = "10.10.1.0/28"
  }
}

# Cloud NAT for outbound internet access
resource "google_compute_router" "sandbox" {
  name    = "sandbox-router"
  region  = var.region
  network = google_compute_network.sandbox.id
  project = var.project_id
}

resource "google_compute_router_nat" "sandbox" {
  name                               = "sandbox-nat"
  router                             = google_compute_router.sandbox.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# -----------------------------------------------------------------------------
# Incus Host (CPU only for staging)
# -----------------------------------------------------------------------------

module "incus_host" {
  source = "../../modules/incus-host"

  project_id   = var.project_id
  region       = var.region
  zone         = var.zone
  environment  = "staging"
  network_id   = google_compute_network.sandbox.id
  subnet_id    = google_compute_subnetwork.sandbox.id

  # Smaller instance for staging
  machine_type = "n2-standard-4"  # 4 vCPU, 16GB RAM
  disk_size_gb = 100

  # No GPU for staging (cost savings)
  enable_gpu = false

  depends_on = [
    google_project_service.compute,
    google_project_service.secretmanager
  ]
}

# -----------------------------------------------------------------------------
# VPC Connector (for Cloud Run to reach Incus)
# -----------------------------------------------------------------------------

resource "google_vpc_access_connector" "sandbox" {
  name          = "sandbox-connector"
  region        = var.region
  project       = var.project_id
  ip_cidr_range = "10.10.2.0/28"
  network       = google_compute_network.sandbox.name
  machine_type  = "e2-micro"
  min_instances = 2
  max_instances = 3
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "incus_host_ip" {
  description = "Incus host internal IP"
  value       = module.incus_host.instance_ip
}

output "incus_host_external_ip" {
  description = "Incus host external IP (for SSH access)"
  value       = module.incus_host.instance_external_ip
}

output "incus_api_url" {
  description = "Incus API URL"
  value       = module.incus_host.incus_api_url
}

output "vpc_connector_name" {
  description = "VPC connector for Cloud Run"
  value       = google_vpc_access_connector.sandbox.name
}

output "client_cert_secret" {
  description = "Secret Manager secret for Incus client certificate"
  value       = module.incus_host.client_cert_secret
}

output "client_key_secret" {
  description = "Secret Manager secret for Incus client key"
  value       = module.incus_host.client_key_secret
}

output "environment_config" {
  description = "Environment variables for Rails app"
  value = <<-EOT
    # Add to your .env or Cloud Run environment:
    SANDBOX_BACKEND=incus
    INCUS_HOST=${module.incus_host.incus_api_url}
    INCUS_PROJECT=agent-sandboxes
    INCUS_CERT_SECRET=${module.incus_host.client_cert_secret}
    INCUS_KEY_SECRET=${module.incus_host.client_key_secret}
  EOT
}
