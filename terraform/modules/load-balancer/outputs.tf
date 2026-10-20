output "ip_address" {
  description = "The external IP address of the load balancer"
  value       = google_compute_global_address.default.address
}

output "url" {
  description = "The public URL of the load balancer (HTTPS if domain configured, HTTP otherwise)"
  value = var.domain != null ? "https://${var.domain}" : (
    var.existing_ssl_cert_name != null ? "https://${google_compute_global_address.default.address}" : "http://${google_compute_global_address.default.address}"
  )
}

output "backend_service_name" {
  description = "Name of the backend service"
  value       = google_compute_backend_service.default.name
}

output "uses_https" {
  description = "Whether the load balancer is configured with HTTPS (requires domain or existing cert)"
  value       = var.domain != null || var.existing_ssl_cert_name != null
}

output "security_policy_name" {
  description = "Name of the Cloud Armor policy on the backend service, or null while enable_security_policy is off"
  value       = var.enable_security_policy ? google_compute_security_policy.default[0].name : null
}
