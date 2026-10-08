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

variable "incus_host_network" {
  description = "Self link of the VPC the Incus host runs in, when that is not this VPC. When set, this VPC peers with it and imports its custom routes, which carry the route to the host's container bridge. Empty (the default) peers with nothing."
  type        = string
  default     = ""
}

variable "incus_host_ranges" {
  description = "Every range of the Incus host's VPC and of its container bridge. While incus_host_network is set, connections opened from these ranges into this VPC are denied, because sandbox code runs there. Replies to connections this VPC opens are not affected."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for range in var.incus_host_ranges :
      !strcontains(range, ":") && can(cidrsubnet(range, 0, 0)) && try(cidrsubnet(range, 0, 0) == range, false)
    ])
    error_message = "Each entry must be an IPv4 network in CIDR form, such as 10.100.0.0/24."
  }
}
