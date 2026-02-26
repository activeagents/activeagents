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

variable "framer_ips" {
  description = "Framer A record IPs for apex domain during migration"
  type        = list(string)
  default     = []
}

variable "framer_www_cname" {
  description = "Framer CNAME target for www subdomain"
  type        = string
  default     = null
}

variable "mx_records" {
  description = "MX records for email (e.g., ['10 mail.example.com.'])"
  type        = list(string)
  default     = []
}

variable "txt_records" {
  description = "TXT records for SPF, DKIM, etc. at apex domain"
  type        = list(string)
  default     = []
}

variable "dmarc_record" {
  description = "DMARC TXT record value"
  type        = string
  default     = null
}

variable "additional_txt_records" {
  description = "Additional TXT records for subdomains (e.g., SPF subdomain)"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "docs_cname" {
  description = "CNAME target for docs subdomain (e.g., activeagents.github.io)"
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
