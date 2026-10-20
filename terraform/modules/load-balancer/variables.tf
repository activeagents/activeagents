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

variable "existing_ssl_cert_name" {
  description = "Name of an existing SSL certificate to use instead of creating a new one. Takes precedence over domain/additional_domains."
  type        = string
  default     = null
}

variable "additional_existing_ssl_cert_names" {
  description = "Names of certificates that already exist in the project and that this proxy serves alongside existing_ssl_cert_name, such as per-domain managed certificates another environment's load balancer issued. A managed certificate stays valid and renews while every domain it covers resolves to a load balancer that serves it, so sharing one lets a second load balancer take a hostname over without a provisioning gap."
  type        = list(string)
  default     = []
}

variable "extra_managed_domains" {
  description = "Domains that each get their own managed SSL certificate attached alongside the primary/existing certificate (e.g., api subdomain or alias domains added after the original cert was issued). Per-domain certs mean an undelegated domain never blocks the others."
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

# -- Cloud Armor ------------------------------------------------------------

variable "enable_security_policy" {
  description = "Attach a Cloud Armor policy to the backend service: blocked_source_ranges are refused with 403, and an address that POSTs to rate_limited_paths more than signup_rate_limit allows is banned for a while."
  type        = bool
  default     = false
}

variable "blocked_source_ranges" {
  description = "Source addresses or CIDR ranges refused outright (e.g. a subscription-bombing bot's addresses). Cloud Armor allows ten per rule; longer lists become several rules."
  type        = list(string)
  default     = []
}

variable "rate_limited_paths" {
  description = "Request paths whose POSTs count toward the rate-based ban. At most four: a Cloud Armor expression holds five sub-expressions, and the method check is one."
  type        = list(string)
  default     = ["/registration", "/newsletter_subscription"]

  validation {
    condition     = length(var.rate_limited_paths) <= 4 && alltrue([for path in var.rate_limited_paths : can(regex("^/[A-Za-z0-9_./-]*$", path))])
    error_message = "rate_limited_paths holds at most four plain paths starting with /."
  }
}

variable "signup_rate_limit" {
  description = "POSTs to rate_limited_paths one address may make per interval before it is banned for ban_duration_sec."
  type = object({
    count            = optional(number, 20)
    interval_sec     = optional(number, 60)
    ban_duration_sec = optional(number, 600)
  })
  default = {}
}

# NOTE: IAP is configured manually via gcloud commands (APIs are deprecated)
# See comments at top of main.tf for instructions
