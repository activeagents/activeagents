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

variable "vpc_connector_id" {
  description = "VPC Access Connector ID for network access"
  type        = string
}

variable "app_service_account" {
  description = "Service account email for the main application"
  type        = string
}

variable "default_sandbox_image" {
  description = "Default Docker image for sandbox execution"
  type        = string
  default     = "gcr.io/cloudrun/hello" # Placeholder, replace with actual sandbox image
}

variable "persistent_sandbox_image" {
  description = "Docker image for persistent sandboxes (notebooks/IDEs)"
  type        = string
  default     = null
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
  description = "Maximum execution time for sandboxes in seconds"
  type        = number
  default     = 300 # 5 minutes
}

variable "max_persistent_sandboxes" {
  description = "Maximum number of persistent sandbox instances"
  type        = number
  default     = 10
}

variable "max_concurrent_sandboxes" {
  description = "Maximum concurrent sandbox executions"
  type        = number
  default     = 20
}

variable "max_sandbox_dispatches_per_second" {
  description = "Maximum sandbox job dispatches per second"
  type        = number
  default     = 10
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
