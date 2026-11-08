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

variable "jobs_instances" {
  description = "Instances of the background jobs service (activeagents-<env>-jobs), which runs Solid Queue with its CPU always allocated. 0 creates no jobs service and runs Solid Queue inside the web instances instead."
  type        = number
  default     = 1

  validation {
    condition     = var.jobs_instances >= 0 && floor(var.jobs_instances) == var.jobs_instances
    error_message = "jobs_instances must be a whole number, 0 or more."
  }
}

variable "jobs_processes" {
  description = "Solid Queue worker processes per jobs instance (JOB_CONCURRENCY in config/queue.yml); each runs the configured threads"
  type        = number
  default     = 1
}

variable "jobs_cpu" {
  description = "CPU of a jobs instance; null takes the web service's"
  type        = string
  default     = null
}

variable "jobs_memory" {
  description = "Memory of a jobs instance; null takes the web service's"
  type        = string
  default     = null
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

variable "secret_volumes" {
  description = "Secret Manager secrets mounted as files in the service and the migrate job, keyed by volume name. Each mounts the secret's latest version as <mount_path>/<file>. secret is a secret ID in this project, or projects/<project>/secrets/<id> for another project. Empty (the default) mounts nothing."
  type = map(object({
    secret     = string
    mount_path = string
    file       = string
  }))
  default = {}
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

variable "ci_service_account" {
  description = "CI/CD service account email to grant invoker access for health checks"
  type        = string
  default     = null
}
