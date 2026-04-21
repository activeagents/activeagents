variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region where Cloud Run service is deployed"
  type        = string
}

variable "name" {
  description = "Base name for load balancer resources"
  type        = string
}

variable "cloud_run_service_name" {
  description = "Name of the Cloud Run service to route traffic to"
  type        = string
}

variable "domain" {
  description = "Primary custom domain for SSL certificate (optional)"
  type        = string
  default     = null
}

variable "additional_domains" {
  description = "Additional domains to include in the SSL certificate (e.g., apex domain)"
  type        = list(string)
  default     = []
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for caching"
  type        = bool
  default     = true
}

variable "enable_http_redirect" {
  description = "Enable HTTP to HTTPS redirect"
  type        = bool
  default     = true
}

# NOTE: IAP is configured manually via gcloud commands (APIs are deprecated)
# See comments at top of main.tf for instructions
