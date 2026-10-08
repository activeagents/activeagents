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

# Cloud Run reaches an Incus host in another VPC (sandbox-staging's
# sandbox-network) through its VPC connector, over this peering. The host's
# VPC exports a static route that sends the container bridge to the host, and
# this side imports it, so the app can poll http://<container_ip>:8080. Peering
# needs a matching peering created from the other VPC, which the host's
# environment declares; it stays INACTIVE until both exist. Subnet ranges on
# the two sides must not overlap.
resource "google_compute_network_peering" "incus_host" {
  count = var.incus_host_network != "" ? 1 : 0

  name         = "activeagents-${var.environment}-incus-host"
  network      = google_compute_network.vpc.self_link
  peer_network = var.incus_host_network

  import_custom_routes = true
  export_custom_routes = false
}

# allow_internal admits all of 10.0.0.0/8, which now includes the host's VPC
# and its bridge. Sandbox code runs there, so nothing there may open a
# connection into this VPC. Firewall rules are stateful: replies to the
# connections Cloud Run opens to the host still arrive.
resource "google_compute_firewall" "deny_from_incus_host" {
  count = var.incus_host_network != "" && length(var.incus_host_ranges) > 0 ? 1 : 0

  project   = var.project_id
  name      = "activeagents-${var.environment}-deny-from-incus-host"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"
  priority  = 900 # ahead of allow_internal, which has the default 1000

  deny {
    protocol = "all"
  }

  source_ranges = var.incus_host_ranges
}
