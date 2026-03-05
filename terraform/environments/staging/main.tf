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
  cpu           = "1"
  memory        = "1Gi"  # Rails 8 requires more memory

  # Database configuration (smaller for staging)
  database_tier = "db-f1-micro"

  # Access control
  allow_public_access   = var.allow_public_access
  authorized_domain     = var.authorized_domain
  ci_service_account    = var.ci_service_account

  # Load Balancer for public access (bypasses org policy restrictions)
  enable_load_balancer = var.enable_load_balancer
  lb_domain            = var.enable_dns ? "staging.${var.dns_domain}" : var.lb_domain
  enable_cdn           = var.enable_cdn

  # IAP for authentication (required since org policy blocks allUsers)
  enable_iap            = var.enable_iap
  iap_support_email     = var.iap_support_email
  iap_authorized_domain = var.iap_authorized_domain

  # DNS configuration
  enable_dns = var.enable_dns
  dns_domain = var.dns_domain

  # Framer website (during migration)
  framer_ips       = var.framer_ips
  framer_www_cname = var.framer_www_cname

  # Email and verification records
  mx_records             = var.mx_records
  txt_records            = var.txt_records
  dmarc_record           = var.dmarc_record
  additional_txt_records = var.additional_txt_records

  # Docs subdomain (GitHub Pages)
  docs_cname = var.docs_cname
}
