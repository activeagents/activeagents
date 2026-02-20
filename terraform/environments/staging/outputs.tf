output "cloud_run_url" {
  description = "Staging Cloud Run service URL"
  value       = module.activeagents.cloud_run_url
}

output "cloud_run_service_name" {
  description = "Staging Cloud Run service name"
  value       = module.activeagents.cloud_run_service_name
}

output "artifact_registry_url" {
  description = "Artifact Registry URL for Docker images"
  value       = module.activeagents.artifact_registry_url
}

# Load Balancer outputs
output "lb_ip_address" {
  description = "External IP address of the load balancer"
  value       = module.activeagents.lb_ip_address
}

output "lb_url" {
  description = "Public URL via load balancer (use this for public access)"
  value       = module.activeagents.lb_url
}

output "public_url" {
  description = "The publicly accessible URL (load balancer if enabled, otherwise Cloud Run URL)"
  value       = module.activeagents.lb_url != null ? module.activeagents.lb_url : module.activeagents.cloud_run_url
}

# DNS outputs
output "dns_name_servers" {
  description = "Name servers for Cloud DNS zone - UPDATE THESE IN GODADDY"
  value       = module.activeagents.dns_name_servers
}

output "staging_domain" {
  description = "Staging domain name"
  value       = module.activeagents.staging_domain
}
