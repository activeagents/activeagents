output "service_name" {
  description = "Cloud Run service name"
  value       = google_cloud_run_v2_service.main.name
}

output "url" {
  description = "Cloud Run service URL"
  value       = google_cloud_run_v2_service.main.uri
}

output "latest_revision" {
  description = "Latest revision name"
  value       = google_cloud_run_v2_service.main.latest_ready_revision
}

output "custom_domain_status" {
  description = "Custom domain mapping status"
  value       = var.domain != null ? google_cloud_run_domain_mapping.main[0].status : null
}
