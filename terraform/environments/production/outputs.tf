output "cloud_run_url" {
  description = "Production Cloud Run service URL (always reachable; the smoke test uses it)"
  value       = module.activeagents.cloud_run_url
}

output "cloud_run_service_name" {
  description = "Production Cloud Run service name"
  value       = module.activeagents.cloud_run_service_name
}

output "artifact_registry_url" {
  description = "Artifact Registry URL for Docker images"
  value       = module.activeagents.artifact_registry_url
}

# Load balancer outputs
output "lb_ip_address" {
  description = "Static IP of the production load balancer: the value staging's dns.tfvars sets public_lb_ip to at the cutover"
  value       = module.activeagents.lb_ip_address
}

output "lb_url" {
  description = "The load balancer by IP (TLS to a bare IP fails SNI validation; use production_url once the domain resolves here)"
  value       = module.activeagents.lb_url
}

output "lb_ssl_certificate_names" {
  description = "Every certificate the production HTTPS proxy serves, own and shared"
  value       = module.activeagents.lb_ssl_certificate_names
}

output "production_domain" {
  description = "Hostname production answers on"
  value       = var.app_host
}

output "production_url" {
  description = "The public URL once activeagents.ai resolves to lb_ip_address"
  value       = "https://${var.app_host}"
}

output "github_app_install_url" {
  description = "Where an account installs the production GitHub App"
  value       = module.activeagents.github_app_install_url
}

output "recordings_bucket" {
  description = "Bucket that holds production session recordings"
  value       = module.activeagents.recordings_bucket
}

output "recordings_signer_email" {
  description = "Service account that signs production recording download URLs"
  value       = module.activeagents.recordings_signer_email
}
