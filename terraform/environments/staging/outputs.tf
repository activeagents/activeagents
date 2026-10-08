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

output "demo_app_url" {
  description = "Public URL of the Support Inbox demo app"
  value       = module.activeagents.demo_app_url
}

output "alias_domain_name_servers" {
  description = "Per-alias-domain Cloud DNS name servers — delegate each domain to these at its registrar"
  value       = module.activeagents.alias_domain_name_servers
}

output "github_app_install_url" {
  description = "Where an account installs the staging GitHub App"
  value       = module.activeagents.github_app_install_url
}

# What sandbox-staging needs to serve this environment (its platform_network
# and platform_egress_ranges variables)
output "vpc_self_link" {
  description = "Self link of the staging VPC, which sandbox-staging's VPC peers with"
  value       = module.activeagents.vpc_self_link
}

output "vpc_connector_cidr" {
  description = "Source range of Cloud Run's traffic into a VPC, which the Incus host's firewall admits"
  value       = module.activeagents.vpc_connector_cidr
}

output "recordings_bucket" {
  description = "Bucket that holds staging session recordings"
  value       = module.activeagents.recordings_bucket
}

output "recordings_signer_email" {
  description = "Service account that signs staging recording download URLs"
  value       = module.activeagents.recordings_signer_email
}
