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

variable "mailer_from_address" {
  description = "Default from address for transactional emails"
  type        = string
  default     = "Active Agent <noreply@staging.activeagents.ai>"
}

variable "allow_public_access" {
  description = "Allow unauthenticated public access to Cloud Run"
  type        = bool
  default     = true  # Org policy reset allows allUsers
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

variable "lb_additional_domains" {
  description = "Additional domains to include in the SSL certificate (e.g., apex domain)"
  type        = list(string)
  default     = []
}

variable "lb_existing_ssl_cert_name" {
  description = "Name of an existing SSL certificate to use instead of creating a new one"
  type        = string
  default     = null
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for caching static assets (disabled when IAP is used)"
  type        = bool
  default     = false  # Disabled since IAP is enabled manually via gcloud
}

# NOTE: IAP is configured manually via gcloud commands since APIs are deprecated
# Commands documented in terraform/modules/load-balancer/main.tf

# DNS configuration
variable "enable_dns" {
  description = "Enable Cloud DNS management for the domain"
  type        = bool
  default     = true
}

variable "dns_domain" {
  description = "Root domain name"
  type        = string
  default     = "activeagents.ai"
}

# Framer website configuration (during migration)
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

# Email configuration
variable "mx_records" {
  description = "MX records for email (e.g., ['1 aspmx.l.google.com.'])"
  type        = list(string)
  default     = []
}

# TXT records
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

# Resource allocation for main app and sandboxes
variable "cpu" {
  description = "CPU allocation for main Cloud Run service"
  type        = string
  default     = "2"  # 2 vCPUs for benchmark API and ActionCable
}

variable "memory" {
  description = "Memory allocation for main Cloud Run service"
  type        = string
  default     = "2Gi"  # 2Gi for Rails 8 + concurrent operations
}

variable "sandbox_cpu" {
  description = "CPU allocation for agent sandbox containers"
  type        = string
  default     = "4"  # 4 vCPUs for parallel Ractor/Thread execution
}

variable "sandbox_memory" {
  description = "Memory allocation for agent sandbox containers"
  type        = string
  default     = "4Gi"  # 4Gi for LLM context and agent workloads
}
