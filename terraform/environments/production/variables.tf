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

# Public signup protection (docs/features/human-check.md). Values go in a
# committed security.auto.tfvars next to this file, as staging's does.
variable "enable_security_policy" {
  description = "Attach the Cloud Armor policy (blocked addresses, signup rate-based ban) to the load balancer"
  type        = bool
  default     = false
}

variable "blocked_source_ranges" {
  description = "Addresses or CIDR ranges the load balancer refuses outright"
  type        = list(string)
  default     = []
}

variable "signup_rate_limit" {
  description = "Signup POSTs one address may make per interval before Cloud Armor bans it"
  type = object({
    count            = optional(number, 20)
    interval_sec     = optional(number, 60)
    ban_duration_sec = optional(number, 600)
  })
  default = {}
}

# Turn on only after activeagents-production-turnstile-secret-key has a version.
variable "enable_turnstile" {
  description = "Pass the Turnstile site and secret keys to the app, which turns on the Turnstile check on the forms"
  type        = bool
  default     = false
}

variable "turnstile_site_key" {
  description = "Site key of the production Turnstile widget (public)"
  type        = string
  default     = ""
}

# -- The app -----------------------------------------------------------------

variable "mailer_from_address" {
  description = "Default from address for transactional emails. Resend must have verified the domain of this address (docs/issues/2026-10-20-email-sender-reputation.md, step 2) before the site serves traffic, or no transactional mail leaves."
  type        = string
  default     = "Active Agent <hello@activeagents.ai>"
}

variable "app_host" {
  description = "Hostname production answers on; links in transactional email (verification, password reset, pilot invitations) use it"
  type        = string
  default     = "activeagents.ai"
}

variable "cpu" {
  description = "CPU allocation for the main Cloud Run service"
  type        = string
  default     = "2"
}

variable "memory" {
  description = "Memory allocation for the main Cloud Run service"
  type        = string
  default     = "2Gi" # Rails 8 + ActionCable + Solid Queue in Puma, as on staging
}

variable "min_instances" {
  description = "Minimum number of Cloud Run instances kept warm"
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 20
}

# -- Billing -----------------------------------------------------------------
# The live-mode Pro prices, committed in billing.auto.tfvars next to this file
# once they exist in the Stripe live account. STRIPE_API_KEY and
# STRIPE_WEBHOOK_SECRET are the activeagents-production-stripe-* secrets.

variable "stripe_pro_monthly_price_id" {
  description = "Live $99/month Pro price (STRIPE_PRO_MONTHLY_PRICE_ID); blank passes nothing and checkout refuses the plan"
  type        = string
  default     = ""
  validation {
    condition     = var.stripe_pro_monthly_price_id == "" || can(regex("^price_[A-Za-z0-9]+$", var.stripe_pro_monthly_price_id))
    error_message = "Expected a Stripe price ID."
  }
}

variable "stripe_pro_annual_price_id" {
  description = "Live $995/year Pro price (STRIPE_PRO_ANNUAL_PRICE_ID); blank passes nothing and checkout refuses the plan"
  type        = string
  default     = ""
  validation {
    condition     = var.stripe_pro_annual_price_id == "" || can(regex("^price_[A-Za-z0-9]+$", var.stripe_pro_annual_price_id))
    error_message = "Expected a Stripe price ID."
  }
}

# -- Access ------------------------------------------------------------------

variable "allow_public_access" {
  description = "Allow unauthenticated access to the Cloud Run service (the load balancer's serverless NEG needs it)"
  type        = bool
  default     = true
}

variable "authorized_domain" {
  description = "Domain granted invoker access when public access is blocked"
  type        = string
  default     = "activeagents.ai"
}

variable "ci_service_account" {
  description = "CI/CD service account email, granted invoker access for the deploy workflow's health check"
  type        = string
  default     = "github-actions@active-agents-platform.iam.gserviceaccount.com"
}

# -- Load balancer and certificates ------------------------------------------
# Committed values live in load_balancer.auto.tfvars next to this file.

variable "enable_load_balancer" {
  description = "Front the Cloud Run service with the external HTTPS load balancer that activeagents.ai resolves to after the cutover"
  type        = bool
  default     = true
}

variable "lb_domain" {
  description = "Primary domain of a managed certificate this environment issues itself. Null while the shared certificate below covers the apex."
  type        = string
  default     = null
}

variable "lb_additional_domains" {
  description = "Further domains on that self-issued certificate"
  type        = list(string)
  default     = []
}

variable "lb_existing_ssl_cert_name" {
  description = "A certificate that already exists in the project and covers the apex and www; the load balancer serves it instead of issuing one"
  type        = string
  default     = null
}

variable "lb_additional_existing_ssl_cert_names" {
  description = "Certificates that already exist in the project and that this load balancer also serves, such as the per-domain certificates staging issued for api.activeagents.ai and the alias domains"
  type        = list(string)
  default     = []
}

variable "lb_extra_managed_domains" {
  description = "Domains this environment issues its own per-domain managed certificate for, each attached alongside the certificates above. A certificate provisions only once its domain resolves to this load balancer."
  type        = list(string)
  default     = []
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for static assets on the backend service"
  type        = bool
  default     = false
}

# Sign in with GitHub. Turn on only after both
# activeagents-production-github-app-client-id and -client-secret have a version.
variable "enable_github_sign_in" {
  description = "Pass the GitHub App client ID and secret to the app, which turns on Sign in with GitHub"
  type        = bool
  default     = false
}

# Sign in with Google. Turn on only after both
# activeagents-production-google-oauth-client-id and -client-secret have a version.
variable "enable_google_sign_in" {
  description = "Pass the Google OAuth client ID and secret to the app, which turns on Sign in with Google"
  type        = bool
  default     = false
}

# GitHub App repository access. Turn on only after
# activeagents-production-github-app-private-key and -webhook-secret have a
# version, in a committed github_app.auto.tfvars next to this file.
variable "enable_github_app" {
  description = "Pass the GitHub App ID, slug, private key and webhook secret to the app"
  type        = bool
  default     = false
}

variable "github_app_id" {
  description = "Numeric App ID of the production GitHub App"
  type        = string
  default     = ""
}

variable "github_app_slug" {
  description = "Slug of the production GitHub App (https://github.com/apps/<slug>)"
  type        = string
  default     = ""
}

# Turn on only after the three activeagents-production-active-record-encryption-*
# secrets hold the values the app derives from secret_key_base today.
variable "enable_active_record_encryption_keys" {
  description = "Pass the explicit Active Record encryption keys to the app"
  type        = bool
  default     = false
}

variable "enable_recordings_storage" {
  description = "Pass the recordings bucket and URL signer to the app"
  type        = bool
  default     = false
}
