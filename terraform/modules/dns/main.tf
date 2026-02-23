# Cloud DNS module for ActiveAgents
# Manages DNS zones and records for the activeagents.ai domain

# Cloud DNS Zone
resource "google_dns_managed_zone" "main" {
  project     = var.project_id
  name        = "activeagents-zone"
  dns_name    = "${var.domain}."
  description = "DNS zone for ${var.domain}"

  dnssec_config {
    state = "on"
  }

  labels = var.labels
}

# Staging A record - points to load balancer
resource "google_dns_record_set" "staging" {
  count        = var.staging_ip != null ? 1 : 0
  project      = var.project_id
  managed_zone = google_dns_managed_zone.main.name
  name         = "staging.${var.domain}."
  type         = "A"
  ttl          = 300
  rrdatas      = [var.staging_ip]
}

# Production A record - points to production load balancer
resource "google_dns_record_set" "production" {
  count        = var.production_ip != null ? 1 : 0
  project      = var.project_id
  managed_zone = google_dns_managed_zone.main.name
  name         = "${var.domain}."
  type         = "A"
  ttl          = 300
  rrdatas      = [var.production_ip]
}

# WWW CNAME - points to Framer during migration, or apex domain in production
resource "google_dns_record_set" "www" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.main.name
  name         = "www.${var.domain}."
  type         = "CNAME"
  ttl          = 300
  # Use Framer CNAME during migration, otherwise point to apex
  rrdatas      = var.framer_www_cname != null ? ["${var.framer_www_cname}."] : ["${var.domain}."]
}

# CAA record - allow Google to issue SSL certificates
resource "google_dns_record_set" "caa" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.main.name
  name         = "${var.domain}."
  type         = "CAA"
  ttl          = 300
  rrdatas      = [
    "0 issue \"pki.goog\"",
    "0 issue \"letsencrypt.org\"",
  ]
}

# MX records (optional - for email)
resource "google_dns_record_set" "mx" {
  count        = length(var.mx_records) > 0 ? 1 : 0
  project      = var.project_id
  managed_zone = google_dns_managed_zone.main.name
  name         = "${var.domain}."
  type         = "MX"
  ttl          = 3600
  rrdatas      = var.mx_records
}

# TXT records (for SPF, DKIM, domain verification, etc.)
resource "google_dns_record_set" "txt" {
  count        = length(var.txt_records) > 0 ? 1 : 0
  project      = var.project_id
  managed_zone = google_dns_managed_zone.main.name
  name         = "${var.domain}."
  type         = "TXT"
  ttl          = 300
  rrdatas      = var.txt_records
}

# Framer A records - keep main site on Framer during migration
# Uses A records because CNAME is not valid for apex domain
resource "google_dns_record_set" "framer_apex" {
  count        = length(var.framer_ips) > 0 && var.production_ip == null ? 1 : 0
  project      = var.project_id
  managed_zone = google_dns_managed_zone.main.name
  name         = "${var.domain}."
  type         = "A"
  ttl          = 300
  rrdatas      = var.framer_ips
}

# DMARC TXT record
resource "google_dns_record_set" "dmarc" {
  count        = var.dmarc_record != null ? 1 : 0
  project      = var.project_id
  managed_zone = google_dns_managed_zone.main.name
  name         = "_dmarc.${var.domain}."
  type         = "TXT"
  ttl          = 3600
  rrdatas      = ["\"${var.dmarc_record}\""]
}

# Additional TXT records for subdomains (SPF subdomain, DKIM, etc.)
resource "google_dns_record_set" "additional_txt" {
  for_each     = { for r in var.additional_txt_records : r.name => r }
  project      = var.project_id
  managed_zone = google_dns_managed_zone.main.name
  name         = "${each.value.name}.${var.domain}."
  type         = "TXT"
  ttl          = 3600
  rrdatas      = ["\"${each.value.value}\""]
}
