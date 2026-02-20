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
