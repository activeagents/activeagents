# Alias domain module: points an entire separate domain (e.g.
# activeagent.dev, activeagent.pro) at the platform load balancer.
# Creates a Cloud DNS zone with apex A + www CNAME + CAA records.
#
# Two-step bring-up: `terraform apply` creates the zone (see the
# name_servers output), then the domain's registrar must delegate NS to
# those name servers. Until delegation happens the domain simply doesn't
# resolve here — and because the load balancer issues a separate managed
# certificate per domain (see modules/load-balancer), a pending domain
# never blocks TLS for the live ones.

resource "google_dns_managed_zone" "alias" {
  project     = var.project_id
  name        = "${replace(var.domain, ".", "-")}-zone"
  dns_name    = "${var.domain}."
  description = "Alias zone for ${var.domain} -> platform load balancer"

  dnssec_config {
    state = "on"
  }

  labels = var.labels
}

resource "google_dns_record_set" "apex" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.alias.name
  name         = "${var.domain}."
  type         = "A"
  ttl          = 300
  rrdatas      = [var.lb_ip]
}

resource "google_dns_record_set" "www" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.alias.name
  name         = "www.${var.domain}."
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["${var.domain}."]
}

# Allow Google-managed certificate issuance
resource "google_dns_record_set" "caa" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.alias.name
  name         = "${var.domain}."
  type         = "CAA"
  ttl          = 300
  rrdatas = [
    "0 issue \"pki.goog\"",
    "0 issue \"letsencrypt.org\"",
  ]
}
