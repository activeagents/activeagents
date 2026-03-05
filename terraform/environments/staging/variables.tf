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
  description = "Enable Cloud CDN for caching static assets (disabled when IAP is used)"
  type        = bool
  default     = false  # Disabled since IAP is enabled
}

# IAP configuration (required since org policy blocks allUsers)
variable "enable_iap" {
  description = "Enable Identity-Aware Proxy for authentication"
  type        = bool
  default     = true
}

variable "iap_support_email" {
  description = "Support email for IAP OAuth consent screen"
  type        = string
  default     = "justin@activeagents.ai"
}

variable "iap_authorized_domain" {
  description = "Domain to grant IAP access"
  type        = string
  default     = "activeagents.ai"
}

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
