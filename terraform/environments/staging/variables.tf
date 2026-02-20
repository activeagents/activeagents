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
