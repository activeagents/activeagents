variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "service_account" {
  description = "Service account email for Cloud Run"
  type        = string
}

variable "vpc_connector_id" {
  description = "VPC Access Connector ID"
  type        = string
}

variable "image" {
  description = "Docker image to deploy"
  type        = string
}

variable "min_instances" {
  description = "Minimum number of instances"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of instances"
  type        = number
  default     = 10
}

variable "cpu" {
  description = "CPU allocation"
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory allocation"
  type        = string
  default     = "512Mi"
}

variable "cloud_sql_connection" {
  description = "Cloud SQL connection name"
  type        = string
}

variable "env_vars" {
  description = "Environment variables"
  type        = map(string)
  default     = {}
}

variable "secret_env_vars" {
  description = "Secret environment variables (Secret Manager secret IDs)"
  type        = map(string)
  default     = {}
}

variable "domain" {
  description = "Custom domain for the service (optional)"
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}

variable "allow_public_access" {
  description = "Allow unauthenticated public access. Set to false if org policy restricts it."
  type        = bool
  default     = true
}

variable "authorized_domain" {
  description = "Domain to grant invoker access (e.g., 'activeagents.ai'). Used when allow_public_access is false."
  type        = string
  default     = null
}
