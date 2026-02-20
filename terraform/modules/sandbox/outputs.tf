output "sandbox_runner_service_account" {
  description = "Service account email for sandbox execution"
  value       = google_service_account.sandbox_runner.email
}

output "sandbox_template_job_name" {
  description = "Name of the sandbox job template"
  value       = google_cloud_run_v2_job.sandbox_template.name
}

output "sandbox_repository_url" {
  description = "Artifact Registry URL for sandbox images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.sandbox_images.repository_id}"
}

output "persistent_sandbox_url" {
  description = "URL of the persistent sandbox service"
  value       = google_cloud_run_v2_service.persistent_sandbox.uri
}

output "sandbox_events_topic" {
  description = "Pub/Sub topic for sandbox events"
  value       = google_pubsub_topic.sandbox_events.id
}

output "sandbox_queue_name" {
  description = "Cloud Tasks queue name for sandbox scheduling"
  value       = google_cloud_tasks_queue.sandbox_queue.name
}
