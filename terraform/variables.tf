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

# Staging billing configuration (never injected into production)
variable "staging_stripe" {
  description = "Staging-only Stripe account and optional existing Pro test price IDs"
  type = object({
    account_id       = optional(string, "")
    monthly_price_id = optional(string, "")
    annual_price_id  = optional(string, "")
  })
  default = {}
}

# Email configuration
variable "mailer_from_address" {
  description = "Default from address for transactional emails"
  type        = string
  default     = "ActiveAgent <hello@activeagents.ai>"
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

variable "max_persistent_sandboxes" {
  description = "Maximum number of persistent sandbox instances"
  type        = number
  default     = 10
}

variable "incus_app_runtime_enabled" {
  description = "Whether the app boots checkout sandboxes (app_runtime) on its Incus host. Keep it off until that host's egress controls are applied: a checkout runs a repository's own code."
  type        = bool
  default     = false
}

# -- Incus sandbox backend --------------------------------------------------

variable "enable_incus_backend" {
  description = "Point the app at this environment's Incus host: SANDBOX_BACKEND=incus, INCUS_HOST from incus_api_url, INCUS_PROJECT, INCUS_CERT_PATH/INCUS_KEY_PATH naming the host's client certificate and key, and INCUS_SERVER_CA_PATH naming the daemon's certificate, mounted from incus-client-cert-<env>, incus-client-key-<env> and incus-server-cert-<env>. Turn on only once all three secrets have a version and Cloud Run can reach the host (docs/infrastructure/app-runtime.md, Connecting staging to its Incus host)."
  type        = bool
  default     = false
}

variable "incus_api_url" {
  description = "The Incus API the app calls (INCUS_HOST): the incus_api_url output of the host's environment, https://<host internal IP>:8443. Required while enable_incus_backend is on."
  type        = string
  default     = ""

  validation {
    condition     = var.incus_api_url == "" || can(regex("^https://[^/:@]+:[0-9]+/?$", var.incus_api_url))
    error_message = "incus_api_url is https://<host>:<port>, such as https://10.10.0.2:8443, or empty. The app has no Unix socket or plain HTTP transport."
  }
}

variable "incus_secret_project" {
  description = "Project that holds incus-client-cert-<env>, incus-client-key-<env> and incus-server-cert-<env>, which the host publishes in the project it runs in. Empty means this project. Prefer the project number: Cloud Run may report a secret from another project by number, and the ID would then show as a change on every plan."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^([a-z][-a-z0-9]{4,28}[a-z0-9]|[0-9]+)?$", var.incus_secret_project))
    error_message = "incus_secret_project is a project ID or number, or empty."
  }
}

variable "incus_host_network" {
  description = "Self link of the Incus host's VPC when it is not this environment's (sandbox-staging's sandbox-network is not). While enable_incus_backend is on, this environment's VPC peers with it and imports the route to the host's container bridge. The host's environment must declare the matching peering. Empty peers with nothing."
  type        = string
  default     = ""

  validation {
    condition     = var.incus_host_network == "" || can(regex("(^|/)projects/[^/]+/global/networks/[^/]+$", var.incus_host_network))
    error_message = "incus_host_network is a VPC self link, such as projects/<project>/global/networks/sandbox-network, or empty."
  }
}

variable "incus_host_ranges" {
  description = "Every range of the Incus host's VPC and container bridge. While the peering exists, connections opened from them into this environment's VPC are denied."
  type        = list(string)
  default     = []
}

# -- Claude Code in sandboxes -----------------------------------------------

variable "claude_code_auth" {
  description = "How Claude Code inside a sandbox authenticates (CLAUDE_CODE_AUTH): api_key, or sandbox_login for a Claude sign-in made inside the sandbox. Passed only when it is not api_key, so the app's own default must stay api_key."
  type        = string
  default     = "api_key"
  nullable    = false

  validation {
    condition     = contains(["api_key", "sandbox_login"], var.claude_code_auth)
    error_message = "claude_code_auth is api_key or sandbox_login."
  }
}

variable "claude_code_hosted_login_enabled" {
  description = "Whether the app offers Claude Code sign-in inside hosted sandboxes (CLAUDE_CODE_HOSTED_LOGIN_ENABLED). Passed only when true, so the app's own default must stay false. Keep it off for everyone but the operator until the Anthropic Commercial Terms and design confirmation of activeagents/activeagent#578 §9 are recorded."
  type        = bool
  default     = false
  nullable    = false
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

# Load Balancer configuration
variable "enable_load_balancer" {
  description = "Enable external load balancer for public access (bypasses org policy)"
  type        = bool
  default     = false
}

variable "lb_domain" {
  description = "Custom domain for the load balancer SSL certificate (optional)"
  type        = string
  default     = null
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
  description = "Whole domains (e.g. activeagent.dev) served by the same load balancer — the app splits landers by host. Each gets a Cloud DNS zone; delegate NS at the registrar after apply."
  type        = list(string)
  default     = []
}

# -- Sign in with GitHub ----------------------------------------------------

variable "enable_github_sign_in" {
  description = "Pass this environment's GitHub App client ID and secret to the app as GITHUB_APP_CLIENT_ID/SECRET, which turns on Sign in with GitHub. Add a version to activeagents-<env>-github-app-client-id and -client-secret first."
  type        = bool
  default     = false
}

# -- GitHub App repository access -------------------------------------------

variable "enable_github_app" {
  description = "Pass this environment's GitHub App to the app: GITHUB_APP_ID and GITHUB_APP_SLUG from github_app_id and github_app_slug, GITHUB_APP_PRIVATE_KEY and GITHUB_APP_WEBHOOK_SECRET from Secret Manager. Add a version to activeagents-<env>-github-app-private-key and -webhook-secret first."
  type        = bool
  default     = false
}

variable "github_app_id" {
  description = "Numeric App ID of this environment's GitHub App. Not a secret; committed per environment."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[0-9]*$", var.github_app_id))
    error_message = "github_app_id is the App's numeric ID, or empty."
  }
}

variable "github_app_slug" {
  description = "Slug of this environment's GitHub App, as in https://github.com/apps/<slug>. Not a secret; committed per environment."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.github_app_slug))
    error_message = "github_app_slug is the lowercase slug from the App's public URL, or empty."
  }
}

# -- Active Record encryption keys ------------------------------------------

variable "enable_active_record_encryption_keys" {
  description = "Pass ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY, _DETERMINISTIC_KEY and _KEY_DERIVATION_SALT from Secret Manager. Each secret must first hold the value the app derives from secret_key_base today (docs/infrastructure/gcp-cicd-setup.md); any other value makes every encrypted column unreadable and stops existing API keys from authenticating."
  type        = bool
  default     = false
}

# -- Session recordings storage ---------------------------------------------

variable "enable_recordings_storage" {
  description = "Pass RECORDINGS_BUCKET and RECORDINGS_SIGNER_EMAIL to the app. The bucket, the signer account and their IAM bindings exist whether or not this is on."
  type        = bool
  default     = false
}

# -- Demo app (examples/support_inbox) --------------------------------------

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
  description = "Trace ingest endpoint the demo app posts to (e.g. https://staging.activeagents.ai/v1/traces)"
  type        = string
  default     = "https://api.activeagents.ai/v1/traces"
}

variable "demo_activeagents_api_key" {
  description = "Workspace telemetry API key for the demo app (copy from the Organization page after signing up)"
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
  description = "Enable Cloud CDN for caching static assets (disable if using IAP)"
  type        = bool
  default     = true
}

# NOTE: IAP is configured manually via gcloud commands (APIs are deprecated)
# See terraform/modules/load-balancer/main.tf for instructions

# DNS configuration
variable "enable_dns" {
  description = "Enable Cloud DNS management for the domain"
  type        = bool
  default     = false
}

variable "dns_domain" {
  description = "Root domain name (e.g., activeagents.ai)"
  type        = string
  default     = "activeagents.ai"
}

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

variable "mx_records" {
  description = "MX records for email (e.g., ['1 aspmx.l.google.com.'])"
  type        = list(string)
  default     = []
}

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

variable "app_host" {
  description = "Hostname this deployment answers on; Rails uses it for links in transactional email (APP_HOST)"
  type        = string
  default     = "activeagents.ai"
}

variable "resend_newsletter_audience_id" {
  description = "Resend audience that confirmed newsletter subscribers are synced into (RESEND_NEWSLETTER_AUDIENCE_ID). The audience id is an identifier, not a credential; the API key stays in Secret Manager."
  type        = string
  default     = "e47ac620-c823-4712-b0fd-f576d8ce132e"
}
