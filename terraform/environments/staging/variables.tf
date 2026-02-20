variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "image" {
  description = "Docker image to deploy"
  type        = string
}

variable "allow_public_access" {
  description = "Allow unauthenticated public access to Cloud Run"
  type        = bool
  default     = false  # GCP org policy may block this
}

variable "authorized_domain" {
  description = "Domain to grant invoker access when public access is blocked"
  type        = string
  default     = "activeagents.ai"
}

variable "ci_service_account" {
  description = "CI/CD service account email for health checks"
  type        = string
  default     = "github-actions@active-agents-platform.iam.gserviceaccount.com"
}

# Load Balancer configuration
variable "enable_load_balancer" {
  description = "Enable external load balancer for public access (bypasses org policy)"
  type        = bool
  default     = true  # Enable by default for staging
}

variable "lb_domain" {
  description = "Custom domain for the load balancer SSL certificate"
  type        = string
  default     = null  # Will use IP address until domain is configured
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for caching static assets"
  type        = bool
  default     = true
}
