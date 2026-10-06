output "cloud_run_url" {
  description = "Production Cloud Run service URL"
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
