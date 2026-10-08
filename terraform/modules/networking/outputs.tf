output "vpc_id" {
  description = "VPC network ID"
  value       = google_compute_network.vpc.id
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "vpc_self_link" {
  description = "VPC network self link"
  value       = google_compute_network.vpc.self_link
}

output "subnet_id" {
  description = "Main subnet ID"
  value       = google_compute_subnetwork.main.id
}

output "vpc_connector_id" {
  description = "VPC Access Connector ID"
  value       = google_vpc_access_connector.connector.id
}

output "vpc_connector_name" {
  description = "VPC Access Connector name"
  value       = google_vpc_access_connector.connector.name
}

output "private_vpc_connection" {
  description = "Private VPC connection for Cloud SQL"
  value       = google_service_networking_connection.private_vpc_connection.id
}

output "vpc_connector_cidr" {
  description = "Range the VPC connector's instances take addresses from: the source address of everything Cloud Run sends into a VPC"
  value       = google_compute_subnetwork.connector.ip_cidr_range
}

output "incus_host_peering" {
  description = "Name of the peering with the Incus host's VPC, or null when incus_host_network is empty"
  value       = one(google_compute_network_peering.incus_host[*].name)
}
