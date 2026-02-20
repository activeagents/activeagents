# Networking module for ActiveAgents
# Creates VPC, subnets, and VPC connector for Cloud Run

resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = "activeagents-${var.environment}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "main" {
  project       = var.project_id
  name          = "activeagents-${var.environment}-main"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  private_ip_google_access = true
}

# Subnet for VPC connector (Serverless VPC Access)
resource "google_compute_subnetwork" "connector" {
  project       = var.project_id
  name          = "activeagents-${var.environment}-connector"
  ip_cidr_range = "10.8.0.0/28"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# VPC Access Connector for Cloud Run to connect to Cloud SQL
resource "google_vpc_access_connector" "connector" {
  project = var.project_id
  name    = "activeagents-${var.environment}"
  region  = var.region

  subnet {
    name = google_compute_subnetwork.connector.name
  }

  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"
}

# Private IP range for Cloud SQL
resource "google_compute_global_address" "private_ip_range" {
  project       = var.project_id
  name          = "activeagents-${var.environment}-sql-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

# Private connection to Google services (for Cloud SQL)
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# Firewall rule to allow internal traffic
resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "activeagents-${var.environment}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/8"]
}
