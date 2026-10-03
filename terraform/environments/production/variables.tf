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
