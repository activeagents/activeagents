variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "secrets" {
  description = "Map of secrets to create"
  type = map(object({
    description = optional(string, "")
  }))
}

variable "accessor_service_accounts" {
  description = "Service accounts that should have access to read secrets"
  type        = list(string)
  default     = null
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
