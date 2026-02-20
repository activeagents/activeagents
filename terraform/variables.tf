# Input variables for ActiveAgents infrastructure

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'."
  }
}

# Cloud Run configuration
variable "image" {
  description = "Docker image to deploy (full path including tag)"
  type        = string
}

variable "min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
}

variable "cpu" {
  description = "CPU allocation for Cloud Run instances"
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory allocation for Cloud Run instances"
  type        = string
  default     = "512Mi"
}

# Database configuration
variable "database_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-f1-micro"
}

# Sandbox configuration (for dynamic agent execution environments)
variable "sandbox_image" {
  description = "Default Docker image for sandbox execution"
  type        = string
  default     = "gcr.io/cloudrun/hello" # Placeholder - replace with actual sandbox image
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
  description = "Maximum execution time for sandboxes"
  type        = number
  default     = 300 # 5 minutes
}

variable "max_concurrent_sandboxes" {
  description = "Maximum concurrent sandbox executions"
  type        = number
  default     = 20
}

# Access control
variable "allow_public_access" {
  description = "Allow unauthenticated public access to Cloud Run. Set to false if GCP org policy restricts it."
  type        = bool
  default     = true
}

variable "authorized_domain" {
  description = "Domain to grant invoker access (e.g., 'activeagents.ai'). Used when allow_public_access is false."
  type        = string
  default     = null
}

variable "ci_service_account" {
  description = "CI/CD service account email to grant invoker access for health checks"
  type        = string
  default     = null
}
