# Demo app module: the Support Inbox example (examples/support_inbox) as a
# public Cloud Run service, so the end-to-end product loop can be tested
# against a real deployment: agents run in the demo app, telemetry POSTs to
# the platform's /v1/traces, traces appear in the workspace dashboard.
#
# Deliberately simple: single instance, ephemeral SQLite (re-seeded on
# boot), no load balancer — the *.run.app URL is the test URL.

resource "random_password" "secret_key_base" {
  length  = 64
  special = false
}

resource "google_cloud_run_v2_service" "demo" {
  project  = var.project_id
  name     = var.name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    scaling {
      min_instance_count = 0
      # One instance: SQLite is per-container, more would split the data
      max_instance_count = 1
    }

    containers {
      image = var.image

      ports {
        container_port = 3000
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        # Telemetry flushes on a background thread between requests
        cpu_idle = false
      }

      env {
        name  = "RAILS_ENV"
        value = "production"
      }
      env {
        name  = "SECRET_KEY_BASE"
        value = random_password.secret_key_base.result
      }
      env {
        name  = "ACTIVEAGENTS_TELEMETRY_ENDPOINT"
        value = var.telemetry_endpoint
      }
      env {
        name  = "ACTIVEAGENTS_API_KEY"
        value = var.activeagents_api_key
      }
      env {
        name  = "AI_PROVIDER"
        value = var.ai_provider
      }

      startup_probe {
        http_get {
          path = "/up"
          port = 3000
        }
        initial_delay_seconds = 10
        period_seconds        = 5
        failure_threshold     = 12
      }
    }

    labels = var.labels
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

# Public access — staging's org policy allows allUsers (see
# allow_public_access in the environment)
resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.allow_public_access ? 1 : 0
  project  = var.project_id
  location = google_cloud_run_v2_service.demo.location
  name     = google_cloud_run_v2_service.demo.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
