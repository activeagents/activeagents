variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "domain" {
  description = "Alias domain to point at the load balancer (e.g. activeagent.dev)"
  type        = string
}

variable "lb_ip" {
  description = "Load balancer IP the apex A record points to"
  type        = string
}

variable "labels" {
  description = "Labels applied to the zone"
  type        = map(string)
  default     = {}
}
