variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "domain" {
  description = "Root domain name (e.g., activeagents.ai)"
  type        = string
}

variable "staging_ip" {
  description = "IP address for staging.domain"
  type        = string
  default     = null
}

variable "production_ip" {
  description = "IP address for production (apex domain)"
  type        = string
  default     = null
}

variable "framer_cname" {
  description = "Framer CNAME target for main site during migration"
  type        = string
  default     = null
}

variable "mx_records" {
  description = "MX records for email (e.g., ['10 mail.example.com.'])"
  type        = list(string)
  default     = []
}

variable "txt_records" {
  description = "TXT records for SPF, DKIM, etc."
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
