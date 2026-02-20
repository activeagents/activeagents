# Outputs from ActiveAgents infrastructure

output "cloud_run_url" {
  description = "URL of the Cloud Run service"
  value       = module.cloud_run.url
}

output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = module.cloud_run.service_name
}

output "artifact_registry_url" {
  description = "URL for pushing Docker images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.activeagents.repository_id}"
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL instance connection name"
  value       = module.cloud_sql.connection_name
}

output "cloud_sql_instance_ip" {
  description = "Cloud SQL instance private IP"
  value       = module.cloud_sql.private_ip
  sensitive   = true
}

output "vpc_connector_id" {
  description = "VPC Access Connector ID for serverless"
  value       = module.networking.vpc_connector_id
}

output "service_account_email" {
  description = "Cloud Run service account email"
  value       = google_service_account.cloud_run.email
}

# Sandbox outputs
output "sandbox_repository_url" {
  description = "Artifact Registry URL for sandbox images"
  value       = module.sandbox.sandbox_repository_url
}

output "sandbox_job_name" {
  description = "Sandbox job template name"
  value       = module.sandbox.sandbox_template_job_name
}

output "sandbox_queue_name" {
  description = "Cloud Tasks queue for sandbox scheduling"
  value       = module.sandbox.sandbox_queue_name
}

output "sandbox_events_topic" {
  description = "Pub/Sub topic for sandbox events"
  value       = module.sandbox.sandbox_events_topic
}

# Load Balancer outputs
output "lb_ip_address" {
  description = "The external IP address of the load balancer"
  value       = var.enable_load_balancer ? module.load_balancer[0].ip_address : null
}

output "lb_url" {
  description = "The public URL via load balancer"
  value       = var.enable_load_balancer ? module.load_balancer[0].url : null
}

# DNS outputs
output "dns_name_servers" {
  description = "Name servers for Cloud DNS zone - configure these in GoDaddy"
  value       = var.enable_dns ? module.dns[0].name_servers : null
}

output "dns_zone_name" {
  description = "Name of the Cloud DNS zone"
  value       = var.enable_dns ? module.dns[0].zone_name : null
}

output "staging_domain" {
  description = "Staging domain name"
  value       = var.enable_dns && var.enable_load_balancer ? "staging.${var.dns_domain}" : null
}
