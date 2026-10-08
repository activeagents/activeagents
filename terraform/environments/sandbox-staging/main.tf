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
  # 1.7 for import blocks with for_each
  required_version = ">= 1.7.0"

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

variable "app_service_account" {
  description = "Service account of the staging app, which reads the Incus client certificate and key (activeagents-<env> in the platform project, created by terraform/main.tf)"
  type        = string
  default     = "activeagents-staging@active-agents-platform.iam.gserviceaccount.com"
}

variable "adopt_existing_incus_secrets" {
  description = "Import incus-client-cert-staging and incus-client-key-staging into state. Set for one apply only when an earlier host created them outside Terraform."
  type        = bool
  default     = false
}

variable "platform_network" {
  description = "Self link of the staging platform's VPC: the vpc_self_link output of terraform/environments/staging (activeagents-staging in active-agents-platform). When set, this VPC peers with it and the host serves the platform's Cloud Run: see platform_egress_ranges. Empty (the default) keeps the host unreachable from the platform."
  type        = string
  default     = ""

  validation {
    condition     = var.platform_network == "" || can(regex("(^|/)projects/[^/]+/global/networks/[^/]+$", var.platform_network))
    error_message = "platform_network is a VPC self link, such as projects/active-agents-platform/global/networks/activeagents-staging, or empty."
  }
}

variable "platform_egress_ranges" {
  description = "Source range of the staging platform's Cloud Run traffic: the subnet of its VPC connector (the vpc_connector_cidr output of terraform/environments/staging). While platform_network is set, only it reaches the Incus API and the containers' port 8080, and the host is given can_ip_forward."
  type        = list(string)
  default     = ["10.8.0.0/28"]
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

  project_id  = var.project_id
  region      = var.region
  zone        = var.zone
  environment = "staging"
  network_id  = google_compute_network.sandbox.id
  subnet_id   = google_compute_subnetwork.sandbox.id

  # Smaller instance for staging
  machine_type = "n2-standard-4" # 4 vCPU, 16GB RAM
  disk_size_gb = 100

  # No GPU for staging (cost savings)
  enable_gpu = false

  app_service_account = var.app_service_account

  # Serving the platform routes the container bridge to the host and admits
  # only the platform's Cloud Run range on 8443 and 8080.
  app_source_ranges = var.platform_network != "" ? var.platform_egress_ranges : []

  depends_on = [
    google_project_service.compute,
    google_project_service.secretmanager
  ]
}

# Once both secrets are in state these blocks import nothing, so the variable
# can go back to false. incus-server-cert-staging is not imported: no host
# created it before Terraform declared it.
import {
  for_each = var.adopt_existing_incus_secrets ? toset(["cert", "key"]) : toset([])
  to       = module.incus_host.google_secret_manager_secret.client_credentials[each.key]
  id       = "projects/${var.project_id}/secrets/incus-client-${each.key}-staging"
}

# -----------------------------------------------------------------------------
# Peering with the staging platform's VPC
# -----------------------------------------------------------------------------

# The staging platform's Cloud Run runs in another project and VPC, and
# reaches this one through its own VPC connector over this peering. This side
# exports the custom route that sends the container bridge to the host; the
# platform's side (terraform/modules/networking, incus_host_network) imports
# it. Each side is applied from its own environment, and the peering is
# ACTIVE once both exist. Subnet ranges on the two sides must not overlap.
resource "google_compute_network_peering" "platform" {
  count = var.platform_network != "" ? 1 : 0

  name         = "sandbox-network-staging-platform"
  network      = google_compute_network.sandbox.self_link
  peer_network = var.platform_network

  export_custom_routes = true
  import_custom_routes = false
}

# -----------------------------------------------------------------------------
# VPC Connector (for Cloud Run to reach Incus)
# -----------------------------------------------------------------------------

# Serves Cloud Run services in this project only. The staging platform runs in
# another project and uses its own connector over the peering above.
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

output "server_cert_secret" {
  description = "Secret Manager secret for the Incus daemon's server certificate"
  value       = module.incus_host.server_cert_secret
}

output "server_cert_command" {
  description = "Makes the running host's server certificate name its internal IP and publishes it; run it from the repository root"
  value       = module.incus_host.server_cert_command
}

output "incus_host_service_account" {
  description = "Service account the Incus host runs as"
  value       = module.incus_host.service_account_email
}

output "egress_acl_command" {
  description = "Applies the sandbox egress ACL to the running host; run it from the repository root"
  value       = module.incus_host.egress_acl_command
}

output "bridge_cidr" {
  description = "Subnet of the host's container bridge, routed to the host while platform_network is set"
  value       = module.incus_host.bridge_cidr
}

output "environment_config" {
  description = "Values that connect the staging platform to this host, for terraform/environments/staging/incus.auto.tfvars. The platform sets the app's INCUS_* variables and mounts the certificate and key itself."
  value       = <<-EOT
    # terraform/environments/staging/incus.auto.tfvars
    # See docs/infrastructure/app-runtime.md (Connecting staging to its Incus host).
    incus_api_url        = "${module.incus_host.incus_api_url}"
    incus_secret_project = "${var.project_id}" # or its project number
    incus_host_network   = "${google_compute_network.sandbox.self_link}"
    incus_host_ranges    = ${jsonencode(concat([google_compute_subnetwork.sandbox.ip_cidr_range], google_compute_subnetwork.sandbox.secondary_ip_range[*].ip_cidr_range, [google_vpc_access_connector.sandbox.ip_cidr_range, module.incus_host.bridge_cidr]))}
  EOT
}
