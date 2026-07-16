# Load Balancer module for Cloud Run with public access
# This bypasses org policy restrictions on direct Cloud Run IAM
#
# NOTE: IAP is configured manually via gcloud since the IAP OAuth APIs are deprecated:
#   gcloud compute backend-services update <backend> --global --no-enable-cdn
#   gcloud compute backend-services update <backend> --global --iap=enabled
#   gcloud iap web add-iam-policy-binding --project=<project> \
#     --member="domain:<domain>" --role="roles/iap.httpsResourceAccessor"

# Serverless NEG pointing to Cloud Run
resource "google_compute_region_network_endpoint_group" "serverless_neg" {
  project               = var.project_id
  name                  = "${var.name}-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = var.cloud_run_service_name
  }
}

# Backend service
resource "google_compute_backend_service" "default" {
  project               = var.project_id
  name                  = "${var.name}-backend"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_region_network_endpoint_group.serverless_neg.id
  }

  # Enable Cloud CDN for caching
  # NOTE: CDN is incompatible with IAP - disable via gcloud if using IAP
  enable_cdn = var.enable_cdn

  dynamic "cdn_policy" {
    for_each = var.enable_cdn ? [1] : []
    content {
      cache_mode                   = "CACHE_ALL_STATIC"
      default_ttl                  = 3600
      max_ttl                      = 86400
      client_ttl                   = 3600
      negative_caching             = true
      serve_while_stale            = 86400
      signed_url_cache_max_age_sec = 0

      cache_key_policy {
        include_host         = true
        include_protocol     = true
        include_query_string = true
      }
    }
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  # IAP is managed manually via gcloud (APIs are deprecated)
  # Prevent Terraform from resetting IAP configuration
  lifecycle {
    ignore_changes = [iap]
  }
}

# URL map
resource "google_compute_url_map" "default" {
  project         = var.project_id
  name            = "${var.name}-urlmap"
  default_service = google_compute_backend_service.default.id
}

# Managed SSL certificate (optional, for custom domain)
# Supports primary domain plus additional domains (e.g., apex + staging)
# Skip creation if using an existing certificate
resource "google_compute_managed_ssl_certificate" "default" {
  count   = var.domain != null && var.existing_ssl_cert_name == null ? 1 : 0
  project = var.project_id
  name    = "${var.name}-cert"

  managed {
    domains = concat([var.domain], var.additional_domains)
  }
}

# Additional managed SSL certificates for domains added after the primary
# certificate was issued (e.g., api.activeagents.ai, activeagent.dev).
# One certificate PER domain, attached alongside the primary/existing
# certificate — SNI picks the right one. Per-domain certs matter: a domain
# whose DNS isn't delegated yet just leaves its own cert PROVISIONING
# without blocking issuance for any other domain, and adding/removing a
# domain never touches the others' certificates.
resource "google_compute_managed_ssl_certificate" "extra" {
  for_each = toset(var.extra_managed_domains)
  project  = var.project_id
  name     = "${var.name}-extra-${replace(each.value, ".", "-")}"

  managed {
    domains = [each.value]
  }
}

# Data source for existing SSL certificate (if specified)
data "google_compute_ssl_certificate" "existing" {
  count   = var.existing_ssl_cert_name != null ? 1 : 0
  project = var.project_id
  name    = var.existing_ssl_cert_name
}

# Local to determine which cert(s) to use
locals {
  ssl_certificate_id = var.existing_ssl_cert_name != null ? data.google_compute_ssl_certificate.existing[0].id : (
    var.domain != null ? google_compute_managed_ssl_certificate.default[0].id : null
  )
  ssl_certificate_ids = concat(
    local.ssl_certificate_id != null ? [local.ssl_certificate_id] : [],
    [for cert in google_compute_managed_ssl_certificate.extra : cert.id]
  )
  https_enabled = var.domain != null || var.existing_ssl_cert_name != null || length(var.extra_managed_domains) > 0
}

# HTTPS proxy (only when a certificate is configured)
resource "google_compute_target_https_proxy" "default" {
  count            = local.https_enabled ? 1 : 0
  project          = var.project_id
  name             = "${var.name}-https-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = local.ssl_certificate_ids
}

# HTTPS forwarding rule (only when a certificate is configured)
resource "google_compute_global_forwarding_rule" "https" {
  count                 = local.https_enabled ? 1 : 0
  project               = var.project_id
  name                  = "${var.name}-https"
  target                = google_compute_target_https_proxy.default[0].id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.default.id
}

# HTTP proxy for direct access (always enabled)
resource "google_compute_target_http_proxy" "default" {
  project = var.project_id
  name    = "${var.name}-http-proxy-direct"
  url_map = google_compute_url_map.default.id
}

# HTTP forwarding rule (for direct HTTP access when HTTPS is not configured)
resource "google_compute_global_forwarding_rule" "http_direct" {
  count                 = local.https_enabled ? 0 : 1
  project               = var.project_id
  name                  = "${var.name}-http-direct"
  target                = google_compute_target_http_proxy.default.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.default.id
}

# Reserve a static IP
resource "google_compute_global_address" "default" {
  project = var.project_id
  name    = "${var.name}-ip"
}

# HTTP to HTTPS redirect (only when HTTPS is configured and redirect enabled)
resource "google_compute_url_map" "http_redirect" {
  count   = local.https_enabled && var.enable_http_redirect ? 1 : 0
  project = var.project_id
  name    = "${var.name}-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "http_redirect" {
  count   = local.https_enabled && var.enable_http_redirect ? 1 : 0
  project = var.project_id
  name    = "${var.name}-http-proxy"
  url_map = google_compute_url_map.http_redirect[0].id
}

resource "google_compute_global_forwarding_rule" "http_redirect" {
  count                 = local.https_enabled && var.enable_http_redirect ? 1 : 0
  project               = var.project_id
  name                  = "${var.name}-http"
  target                = google_compute_target_http_proxy.http_redirect[0].id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.default.id
}
