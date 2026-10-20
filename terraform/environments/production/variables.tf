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
