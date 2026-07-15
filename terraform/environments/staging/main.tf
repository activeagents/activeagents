# Staging environment configuration for ActiveAgents

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
  environment = "staging"

  # Cloud Run configuration
  image         = var.image
  min_instances = 0  # Scale to zero for cost savings
  max_instances = 5
  cpu           = var.cpu      # 2 vCPUs for benchmark API and concurrent operations
  memory        = var.memory   # 2Gi for Rails 8 + ActionCable

  # Email configuration
  mailer_from_address = var.mailer_from_address

  # Sandbox configuration for agent execution (ephemeral containers)
  sandbox_cpu              = var.sandbox_cpu     # 4 vCPUs for parallel Ractor/Thread execution
  sandbox_memory           = var.sandbox_memory  # 4Gi for LLM context and agent workloads
  max_persistent_sandboxes = 3                   # Limited by quota (4 CPUs × 3 = 12 < 20 quota)

  # Database configuration (smaller for staging)
  database_tier = "db-f1-micro"

  # Access control
  allow_public_access   = var.allow_public_access
  authorized_domain     = var.authorized_domain
  ci_service_account    = var.ci_service_account

  # Load Balancer for public access (bypasses org policy restrictions)
  # NOTE: IAP is configured manually via gcloud (see modules/load-balancer/main.tf)
  enable_load_balancer      = var.enable_load_balancer
  lb_domain                 = var.lb_existing_ssl_cert_name == null ? (var.enable_dns ? "staging.${var.dns_domain}" : var.lb_domain) : null
  # Include apex domain in SSL cert when enable_apex_domain is true (only if not using existing cert)
  lb_additional_domains     = var.lb_existing_ssl_cert_name == null && var.enable_apex_domain ? [var.dns_domain] : var.lb_additional_domains
  # Use existing SSL cert if specified (avoids provisioning delays)
  lb_existing_ssl_cert_name = var.lb_existing_ssl_cert_name
  # Domains added after the existing cert was issued (e.g., api.activeagents.ai)
  # get their own managed cert attached alongside it
  lb_extra_managed_domains  = var.lb_extra_managed_domains
  enable_cdn                = var.enable_cdn

  # DNS configuration
  enable_dns = var.enable_dns
  dns_domain = var.dns_domain

  # Apex domain - point activeagents.ai to LB instead of Framer
  enable_apex_domain = var.enable_apex_domain

  # Framer website (during migration)
  framer_ips       = var.framer_ips
  framer_www_cname = var.framer_www_cname

  # Email and verification records
  mx_records             = var.mx_records
  txt_records            = var.txt_records
  dmarc_record           = var.dmarc_record
  additional_txt_records = var.additional_txt_records

  # Subdomain email records (e.g., Loops dev.activeagents.ai)
  subdomain_mx_records     = var.subdomain_mx_records
  additional_cname_records = var.additional_cname_records

  # Docs subdomain (GitHub Pages)
  docs_cname = var.docs_cname
}
