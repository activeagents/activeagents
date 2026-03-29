# Input variables for ActiveAgents infrastructure

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'."
  }
}

# Email configuration
variable "mailer_from_address" {
  description = "Default from address for transactional emails"
  type        = string
  default     = "ActiveAgent <hello@activeagents.ai>"
}

# Cloud Run configuration
variable "image" {
  description = "Docker image to deploy (full path including tag)"
  type        = string
}

variable "min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
}

variable "cpu" {
  description = "CPU allocation for Cloud Run instances"
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory allocation for Cloud Run instances"
  type        = string
  default     = "512Mi"
}

# Database configuration
variable "database_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-f1-micro"
}

# Sandbox configuration (for dynamic agent execution environments)
variable "sandbox_image" {
  description = "Default Docker image for sandbox execution"
  type        = string
  default     = "gcr.io/cloudrun/hello" # Placeholder - replace with actual sandbox image
}

variable "sandbox_cpu" {
  description = "CPU allocation for sandbox containers"
  type        = string
  default     = "1"
}

variable "sandbox_memory" {
  description = "Memory allocation for sandbox containers"
  type        = string
  default     = "512Mi"
}

variable "sandbox_timeout_seconds" {
  description = "Maximum execution time for sandboxes"
  type        = number
  default     = 300 # 5 minutes
}

variable "max_concurrent_sandboxes" {
  description = "Maximum concurrent sandbox executions"
  type        = number
  default     = 20
}

variable "max_persistent_sandboxes" {
  description = "Maximum number of persistent sandbox instances"
  type        = number
  default     = 10
}

# Access control
variable "allow_public_access" {
  description = "Allow unauthenticated public access to Cloud Run. Set to false if GCP org policy restricts it."
  type        = bool
  default     = true
}

variable "authorized_domain" {
  description = "Domain to grant invoker access (e.g., 'activeagents.ai'). Used when allow_public_access is false."
  type        = string
  default     = null
}

variable "ci_service_account" {
  description = "CI/CD service account email to grant invoker access for health checks"
  type        = string
  default     = null
}

# Load Balancer configuration
variable "enable_load_balancer" {
  description = "Enable external load balancer for public access (bypasses org policy)"
  type        = bool
  default     = false
}

variable "lb_domain" {
  description = "Custom domain for the load balancer SSL certificate (optional)"
  type        = string
  default     = null
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for caching static assets (disable if using IAP)"
  type        = bool
  default     = true
}

# NOTE: IAP is configured manually via gcloud commands (APIs are deprecated)
# See terraform/modules/load-balancer/main.tf for instructions

# DNS configuration
variable "enable_dns" {
  description = "Enable Cloud DNS management for the domain"
  type        = bool
  default     = false
}

variable "dns_domain" {
  description = "Root domain name (e.g., activeagents.ai)"
  type        = string
  default     = "activeagents.ai"
}

variable "enable_apex_domain" {
  description = "Point apex domain (activeagents.ai) to the load balancer instead of Framer"
  type        = bool
  default     = false
}

variable "framer_ips" {
  description = "Framer A record IPs for apex domain during migration"
  type        = list(string)
  default     = []
}

variable "framer_www_cname" {
  description = "Framer CNAME target for www subdomain (e.g., sites.framer.app)"
  type        = string
  default     = null
}

variable "mx_records" {
  description = "MX records for email (e.g., ['1 aspmx.l.google.com.'])"
  type        = list(string)
  default     = []
}

variable "txt_records" {
  description = "TXT records for SPF, DKIM, domain verification"
  type        = list(string)
  default     = []
}

variable "dmarc_record" {
  description = "DMARC TXT record value (without quotes)"
  type        = string
  default     = null
}

variable "additional_txt_records" {
  description = "Additional TXT records for subdomains (e.g., SPF subdomain)"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "docs_cname" {
  description = "CNAME target for docs subdomain (e.g., activeagents.github.io)"
  type        = string
  default     = null
}

# Subdomain email configuration (e.g., for Loops sending domains)
variable "subdomain_mx_records" {
  description = "MX records for subdomains (e.g., envelope.dev for Loops)"
  type = list(object({
    name   = string
    values = list(string)
  }))
  default = []
}

variable "additional_cname_records" {
  description = "Additional CNAME records (e.g., DKIM for email)"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}
