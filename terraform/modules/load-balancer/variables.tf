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
  description = "Custom domain for SSL certificate (optional)"
  type        = string
  default     = null
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

# IAP configuration
variable "enable_iap" {
  description = "Enable Identity-Aware Proxy for authentication (disables CDN)"
  type        = bool
  default     = false
}

variable "iap_support_email" {
  description = "Support email for IAP OAuth consent screen"
  type        = string
  default     = null
}

variable "iap_application_title" {
  description = "Application title for IAP OAuth consent screen"
  type        = string
  default     = "ActiveAgents Staging"
}

variable "iap_authorized_domain" {
  description = "Domain to grant IAP access (e.g., 'activeagents.ai')"
  type        = string
  default     = null
}
