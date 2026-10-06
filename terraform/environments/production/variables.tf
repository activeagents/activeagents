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

# Sign in with GitHub. Turn on only after both
# activeagents-production-github-app-client-id and -client-secret have a version.
variable "enable_github_sign_in" {
  description = "Pass the GitHub App client ID and secret to the app, which turns on Sign in with GitHub"
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
