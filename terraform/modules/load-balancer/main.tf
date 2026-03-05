# Load Balancer module for Cloud Run with public access
# This bypasses org policy restrictions on direct Cloud Run IAM

# Get project number for IAP brand
data "google_project" "current" {
  project_id = var.project_id
}

# IAP OAuth brand (consent screen) - required for IAP
resource "google_iap_brand" "default" {
  count             = var.enable_iap ? 1 : 0
  support_email     = var.iap_support_email
  application_title = var.iap_application_title
  project           = data.google_project.current.number
}

# IAP OAuth client
resource "google_iap_client" "default" {
  count        = var.enable_iap ? 1 : 0
  display_name = "${var.name}-iap-client"
  brand        = google_iap_brand.default[0].name
}

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

  # Enable Cloud CDN for caching (disabled when IAP is enabled - they're incompatible)
  enable_cdn = var.enable_iap ? false : var.enable_cdn

  dynamic "cdn_policy" {
    for_each = var.enable_cdn && !var.enable_iap ? [1] : []
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

  # Enable Identity-Aware Proxy for authentication
  dynamic "iap" {
    for_each = var.enable_iap ? [1] : []
    content {
      oauth2_client_id     = google_iap_client.default[0].client_id
      oauth2_client_secret = google_iap_client.default[0].secret
    }
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# URL map
resource "google_compute_url_map" "default" {
  project         = var.project_id
  name            = "${var.name}-urlmap"
  default_service = google_compute_backend_service.default.id
}

# Managed SSL certificate (optional, for custom domain)
resource "google_compute_managed_ssl_certificate" "default" {
  count   = var.domain != null ? 1 : 0
  project = var.project_id
  name    = "${var.name}-cert"

  managed {
    domains = [var.domain]
  }
}

# HTTPS proxy (only when domain is configured)
resource "google_compute_target_https_proxy" "default" {
  count            = var.domain != null ? 1 : 0
  project          = var.project_id
  name             = "${var.name}-https-proxy"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default[0].id]
}

# HTTPS forwarding rule (only when domain is configured)
resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.domain != null ? 1 : 0
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

# HTTP forwarding rule (for direct HTTP access when no domain)
resource "google_compute_global_forwarding_rule" "http_direct" {
  count                 = var.domain == null ? 1 : 0
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

# HTTP to HTTPS redirect (only when domain is configured and redirect enabled)
resource "google_compute_url_map" "http_redirect" {
  count   = var.domain != null && var.enable_http_redirect ? 1 : 0
  project = var.project_id
  name    = "${var.name}-http-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "http_redirect" {
  count   = var.domain != null && var.enable_http_redirect ? 1 : 0
  project = var.project_id
  name    = "${var.name}-http-proxy"
  url_map = google_compute_url_map.http_redirect[0].id
}

resource "google_compute_global_forwarding_rule" "http_redirect" {
  count                 = var.domain != null && var.enable_http_redirect ? 1 : 0
  project               = var.project_id
  name                  = "${var.name}-http"
  target                = google_compute_target_http_proxy.http_redirect[0].id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.default.id
}

# IAP access for authorized domain
resource "google_iap_web_backend_service_iam_member" "domain_access" {
  count               = var.enable_iap && var.iap_authorized_domain != null ? 1 : 0
  project             = var.project_id
  web_backend_service = google_compute_backend_service.default.name
  role                = "roles/iap.httpsResourceAccessor"
  member              = "domain:${var.iap_authorized_domain}"
}
