# Cloud Run module for ActiveAgents

resource "google_cloud_run_v2_service" "main" {
  project  = var.project_id
  name     = "activeagents-${var.environment}"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.service_account

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = var.image

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      # Plain environment variables
      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      # Secret environment variables from Secret Manager
      dynamic "env" {
        for_each = var.secret_env_vars
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }

      ports {
        container_port = 80
      }

      startup_probe {
        http_get {
          path = "/up"
          port = 80
        }
        initial_delay_seconds = 5
        timeout_seconds       = 3
        period_seconds        = 5
        failure_threshold     = 30
      }

      liveness_probe {
        http_get {
          path = "/up"
          port = 80
        }
        timeout_seconds   = 3
        period_seconds    = 30
        failure_threshold = 3
      }

      # Cloud SQL connection
      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.cloud_sql_connection]
      }
    }

    timeout         = "300s"
    max_instance_request_concurrency = 80

    labels = var.labels
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  labels = var.labels

  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }
}

# Allow unauthenticated access (public web app)
# Note: This may fail if GCP org policy restricts public access
# In that case, set allow_public_access = false
resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.allow_public_access ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.main.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Allow domain-based access (when public access is blocked by org policy)
resource "google_cloud_run_v2_service_iam_member" "domain" {
  count    = var.authorized_domain != null ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.main.name
  role     = "roles/run.invoker"
  member   = "domain:${var.authorized_domain}"
}

# Custom domain mapping (optional, configured if domain is provided)
resource "google_cloud_run_domain_mapping" "main" {
  count    = var.domain != null ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = var.domain

  metadata {
    namespace = var.project_id
    labels    = var.labels
  }

  spec {
    route_name = google_cloud_run_v2_service.main.name
  }
}
