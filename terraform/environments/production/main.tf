# Production environment configuration for ActiveAgents
#
# What this environment owns: the activeagents-production Cloud Run service
# and migrate job, its VPC, Cloud SQL instance, secrets, sandbox
# infrastructure, recordings bucket, and the external HTTPS load balancer
# that activeagents.ai resolves to once staging's dns.tfvars names its IP.
#
# What it does not own: the activeagents.ai DNS zone and its records, and the
# alias-domain zones. They were created from the staging environment and stay
# in its state; the public_lb_ip variable there is the cutover switch.
# docs/infrastructure/production-environment.md walks through bringing this
# environment up and moving the domain to it.

terraform {
  required_version = ">= 1.5.0"
  # Backend configured in backend.tf
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

module "activeagents" {
  source = "../../"

  project_id  = var.project_id
  region      = var.region
  environment = "production"

  # Cloud Run configuration (production-scale)
  image         = var.image
  min_instances = var.min_instances # Always keep at least 1 instance warm
  max_instances = var.max_instances
  cpu           = var.cpu
  memory        = var.memory

  # Email and links
  mailer_from_address = var.mailer_from_address
  app_host            = var.app_host

  # Live-mode Pro prices (billing.auto.tfvars)
  stripe_pro_price_ids = {
    monthly = var.stripe_pro_monthly_price_id
    annual  = var.stripe_pro_annual_price_id
  }

  # Checkout sandboxes on the Incus host stay off until its egress controls
  # (https://github.com/activeagents/activeagents/issues/150) are applied.
  incus_app_runtime_enabled = false

  # Production has no Incus host of its own yet. Claude Code sign-in in
  # sandboxes keeps its defaults (api_key, hosted login off).
  enable_incus_backend = false

  # Database configuration (production-scale, regional, deletion-protected)
  database_tier = "db-custom-2-4096" # 2 vCPUs, 4GB RAM

  # Public signup protection: Cloud Armor in front of the load balancer and
  # Cloudflare Turnstile on the forms (docs/features/human-check.md).
  enable_security_policy = var.enable_security_policy
  blocked_source_ranges  = var.blocked_source_ranges
  signup_rate_limit      = var.signup_rate_limit
  enable_turnstile       = var.enable_turnstile
  turnstile_site_key     = var.turnstile_site_key

  # Access control
  allow_public_access = var.allow_public_access
  authorized_domain   = var.authorized_domain
  ci_service_account  = var.ci_service_account

  # Load balancer: the static IP the public hostnames move to. The
  # certificates come from load_balancer.auto.tfvars.
  enable_load_balancer      = var.enable_load_balancer
  lb_domain                 = var.lb_domain
  lb_additional_domains     = var.lb_additional_domains
  lb_existing_ssl_cert_name = var.lb_existing_ssl_cert_name
  lb_extra_managed_domains  = var.lb_extra_managed_domains
  enable_cdn                = var.enable_cdn

  lb_additional_existing_ssl_cert_names = var.lb_additional_existing_ssl_cert_names

  # DNS stays with the staging environment's state, which created the zone.
  # Enabling it here would try to create the same zone a second time.
  enable_dns = false

  # Sign in with GitHub, through this environment's GitHub App, and Sign in
  # with Google, through its OAuth client
  enable_github_sign_in = var.enable_github_sign_in
  enable_google_sign_in = var.enable_google_sign_in

  # GitHub App repository access, encryption keys and recordings storage.
  # Each flag stays off until docs/infrastructure/gcp-cicd-setup.md says to
  # turn it on.
  enable_github_app                    = var.enable_github_app
  github_app_id                        = var.github_app_id
  github_app_slug                      = var.github_app_slug
  enable_active_record_encryption_keys = var.enable_active_record_encryption_keys
  enable_recordings_storage            = var.enable_recordings_storage
}
