variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "stripe_expected_account_id" {
  description = "Verified Stripe sandbox account ID; setup refuses a different account"
  type        = string
  default     = ""
  validation {
    condition     = var.stripe_expected_account_id == "" || can(regex("^acct_[A-Za-z0-9]+$", var.stripe_expected_account_id))
    error_message = "Expected a Stripe account ID."
  }
}

variable "stripe_pro_monthly_price_id" {
  description = "Existing $99/month Pro test price; blank discovers or creates it safely"
  type        = string
  default     = ""
  validation {
    condition     = var.stripe_pro_monthly_price_id == "" || can(regex("^price_[A-Za-z0-9]+$", var.stripe_pro_monthly_price_id))
    error_message = "Expected a Stripe price ID."
  }
}

variable "stripe_pro_annual_price_id" {
  description = "Existing $995/year Pro test price; blank discovers or creates it safely"
  type        = string
  default     = ""
  validation {
    condition     = var.stripe_pro_annual_price_id == "" || can(regex("^price_[A-Za-z0-9]+$", var.stripe_pro_annual_price_id))
    error_message = "Expected a Stripe price ID."
  }
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "image" {
  description = "Docker image to deploy"
  type        = string
}

variable "mailer_from_address" {
  description = "Default from address for transactional emails"
  type        = string
  default     = "Active Agent <noreply@staging.activeagents.ai>"
}

variable "app_host" {
  description = "Hostname staging answers on; links in transactional email (verification, newsletter confirmation) use it"
  type        = string
  default     = "staging.activeagents.ai"
}

variable "allow_public_access" {
  description = "Allow unauthenticated public access to Cloud Run"
  type        = bool
  default     = true # Org policy reset allows allUsers
}

variable "authorized_domain" {
  description = "Domain to grant invoker access when public access is blocked"
  type        = string
  default     = "activeagents.ai"
}

variable "ci_service_account" {
  description = "CI/CD service account email for health checks"
  type        = string
  default     = "github-actions@active-agents-platform.iam.gserviceaccount.com"
}

# Load Balancer configuration
variable "enable_load_balancer" {
  description = "Enable external load balancer for public access (bypasses org policy)"
  type        = bool
  default     = true # Enable by default for staging
}

variable "lb_domain" {
  description = "Custom domain for the load balancer SSL certificate"
  type        = string
  default     = null # Will use IP address until domain is configured
}

variable "lb_additional_domains" {
  description = "Additional domains to include in the SSL certificate (e.g., apex domain)"
  type        = list(string)
  default     = []
}

variable "lb_existing_ssl_cert_name" {
  description = "Name of an existing SSL certificate to use instead of creating a new one"
  type        = string
  default     = null
}

variable "lb_extra_managed_domains" {
  description = "Domains covered by an additional managed SSL certificate attached alongside the primary/existing one (e.g., api.activeagents.ai)"
  type        = list(string)
  default     = []
}

variable "alias_domains" {
  description = "Whole domains (e.g. activeagent.dev) served by the same load balancer with host-split landers"
  type        = list(string)
  default     = []
}

variable "enable_demo_app" {
  description = "Deploy the Support Inbox example app as a public Cloud Run service"
  type        = bool
  default     = false
}

variable "demo_app_image" {
  description = "Container image for the demo app (built from examples/support_inbox)"
  type        = string
  default     = ""
}

variable "demo_telemetry_endpoint" {
  description = "Trace ingest endpoint the demo app posts to"
  type        = string
  default     = "https://staging.activeagents.ai/v1/traces"
}

variable "demo_activeagents_api_key" {
  description = "Workspace telemetry API key for the demo app (Organization page)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "demo_ai_provider" {
  description = "Provider the demo agents use: mock (no credentials), openai, anthropic"
  type        = string
  default     = "mock"
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for caching static assets (disabled when IAP is used)"
  type        = bool
  default     = false # Disabled since IAP is enabled manually via gcloud
}

# NOTE: IAP is configured manually via gcloud commands since APIs are deprecated
# Commands documented in terraform/modules/load-balancer/main.tf

# DNS configuration
variable "enable_dns" {
  description = "Enable Cloud DNS management for the domain"
  type        = bool
  default     = true
}

variable "dns_domain" {
  description = "Root domain name"
  type        = string
  default     = "activeagents.ai"
}

# Framer website configuration (during migration)
variable "enable_apex_domain" {
  description = "Point apex domain (activeagents.ai) to the load balancer instead of Framer"
  type        = bool
  default     = false
}

variable "framer_ips" {
  description = "Framer A record IPs for apex domain during migration"
  type        = list(string)
  default     = []
}

variable "framer_www_cname" {
  description = "Framer CNAME target for www subdomain (e.g., sites.framer.app)"
  type        = string
  default     = null
}

# Email configuration
variable "mx_records" {
  description = "MX records for email (e.g., ['1 aspmx.l.google.com.'])"
  type        = list(string)
  default     = []
}

# TXT records
variable "txt_records" {
  description = "TXT records for SPF, DKIM, domain verification"
  type        = list(string)
  default     = []
}

variable "dmarc_record" {
  description = "DMARC TXT record value (without quotes)"
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

# Subdomain email configuration (e.g., for Loops sending domains)
variable "subdomain_mx_records" {
  description = "MX records for subdomains (e.g., envelope.dev for Loops)"
  type = list(object({
    name   = string
    values = list(string)
  }))
  default = []
}

variable "additional_cname_records" {
  description = "Additional CNAME records (e.g., DKIM for email)"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

# Resource allocation for main app and sandboxes
variable "cpu" {
  description = "CPU allocation for main Cloud Run service"
  type        = string
  default     = "2" # 2 vCPUs for benchmark API and ActionCable
}

variable "memory" {
  description = "Memory allocation for main Cloud Run service"
  type        = string
  default     = "2Gi" # 2Gi for Rails 8 + concurrent operations
}

variable "sandbox_cpu" {
  description = "CPU allocation for agent sandbox containers"
  type        = string
  default     = "4" # 4 vCPUs for parallel Ractor/Thread execution
}

variable "sandbox_memory" {
  description = "Memory allocation for agent sandbox containers"
  type        = string
  default     = "4Gi" # 4Gi for LLM context and agent workloads
}

# Sign in with GitHub. Turn on only after both
# activeagents-staging-github-app-client-id and -client-secret have a version.
variable "enable_github_sign_in" {
  description = "Pass the GitHub App client ID and secret to the app, which turns on Sign in with GitHub"
  type        = bool
  default     = false
}

# GitHub App repository access. Turn on only after
# activeagents-staging-github-app-private-key and -webhook-secret have a version,
# in a committed github_app.auto.tfvars next to this file.
variable "enable_github_app" {
  description = "Pass the GitHub App ID, slug, private key and webhook secret to the app"
  type        = bool
  default     = false
}

variable "github_app_id" {
  description = "Numeric App ID of the staging GitHub App"
  type        = string
  default     = ""
}

variable "github_app_slug" {
  description = "Slug of the staging GitHub App (https://github.com/apps/<slug>)"
  type        = string
  default     = ""
}

# Turn on only after the three activeagents-staging-active-record-encryption-*
# secrets hold the values the app derives from secret_key_base today.
variable "enable_active_record_encryption_keys" {
  description = "Pass the explicit Active Record encryption keys to the app"
  type        = bool
  default     = false
}

variable "enable_recordings_storage" {
  description = "Pass the recordings bucket and URL signer to the app"
  type        = bool
  default     = false
}

# The sandbox-staging Incus host. Every value below is committed in
# incus.auto.tfvars next to this file once docs/infrastructure/app-runtime.md
# (Connecting staging to its Incus host) says to set it. The defaults match
# terraform/environments/sandbox-staging; check them against its outputs.
variable "enable_incus_backend" {
  description = "Point the app at the sandbox-staging Incus host. Turn on only once incus-client-cert-staging, incus-client-key-staging and incus-server-cert-staging have a version and Cloud Run can reach the host."
  type        = bool
  default     = false
}

variable "incus_api_url" {
  description = "The incus_api_url output of sandbox-staging, https://<host internal IP>:8443"
  type        = string
  default     = ""
}

variable "incus_secret_project" {
  description = "Project (number preferred) holding the incus-client-cert-, incus-client-key- and incus-server-cert-staging secrets: sandbox-staging's project_id"
  type        = string
  default     = "activeagents-staging"
}

variable "incus_host_network" {
  description = "Self link of sandbox-staging's VPC (its environment_config output gives it). Empty peers with nothing, and Cloud Run cannot reach a host in another VPC."
  type        = string
  default     = ""
}

variable "incus_host_ranges" {
  description = "sandbox-staging's subnet, connector and container bridge ranges, denied from opening connections into this VPC"
  type        = list(string)
  default     = ["10.10.0.0/24", "10.10.1.0/28", "10.10.2.0/28", "10.100.0.0/24"]
}

# Checkout sandboxes stay off until the host's egress controls
# (https://github.com/activeagents/activeagents/issues/150) are applied.
variable "incus_app_runtime_enabled" {
  description = "Let the app boot checkout sandboxes (app_runtime) on the Incus host"
  type        = bool
  default     = false
}

variable "claude_code_auth" {
  description = "How Claude Code in a sandbox authenticates: api_key or sandbox_login"
  type        = string
  default     = "api_key"

  validation {
    condition     = contains(["api_key", "sandbox_login"], var.claude_code_auth)
    error_message = "claude_code_auth is api_key or sandbox_login."
  }
}

# Stays off for everyone but the operator until the gate in
# activeagents/activeagent#578 §9 is recorded.
variable "claude_code_hosted_login_enabled" {
  description = "Offer Claude Code sign-in inside hosted sandboxes"
  type        = bool
  default     = false
}
