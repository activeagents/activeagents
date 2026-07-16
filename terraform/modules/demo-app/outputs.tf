output "url" {
  description = "Public URL of the demo app"
  value       = google_cloud_run_v2_service.demo.uri
}

output "service_name" {
  description = "Cloud Run service name"
  value       = google_cloud_run_v2_service.demo.name
}
