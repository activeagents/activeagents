variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "name" {
  description = "Cloud Run service name for the demo app"
  type        = string
}

variable "image" {
  description = "Container image for the demo app (examples/support_inbox)"
  type        = string
}

variable "telemetry_endpoint" {
  description = "ActiveAgents trace ingest endpoint the demo app posts to"
  type        = string
  default     = "https://api.activeagents.ai/v1/traces"
}

variable "activeagents_api_key" {
  description = "Workspace telemetry API key (Organization page) the demo app authenticates with"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ai_provider" {
  description = "Provider the demo agents generate with (mock needs no credentials)"
  type        = string
  default     = "mock"
}

variable "allow_public_access" {
  description = "Grant allUsers run.invoker on the demo service"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels applied to the service"
  type        = map(string)
  default     = {}
}
