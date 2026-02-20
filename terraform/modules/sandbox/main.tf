# Sandbox Infrastructure Module
# Provides dynamic container execution environments similar to HuggingFace Spaces or Google Colab
#
# This module sets up the infrastructure for running isolated agent sandboxes:
# - Cloud Run Jobs for one-off executions
# - Cloud Run Services for persistent sandboxes
# - Isolated networking per sandbox
# - Resource quotas and timeouts

# Service account for sandbox execution
resource "google_service_account" "sandbox_runner" {
  project      = var.project_id
  account_id   = "sandbox-runner-${var.environment}"
  display_name = "Sandbox Runner (${var.environment})"
}

# Limited permissions for sandboxes (security)
resource "google_project_iam_member" "sandbox_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.sandbox_runner.email}"
}

resource "google_project_iam_member" "sandbox_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.sandbox_runner.email}"
}

# Artifact Registry for sandbox images
resource "google_artifact_registry_repository" "sandbox_images" {
  project       = var.project_id
  location      = var.region
  repository_id = "activeagents-sandboxes-${var.environment}"
  description   = "Container images for agent sandboxes"
  format        = "DOCKER"

  labels = var.labels

  # Cleanup old images to save cost
  cleanup_policies {
    id     = "keep-minimum-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-old-images"
    action = "DELETE"
    condition {
      older_than = "2592000s" # 30 days
    }
  }
}

# Base sandbox job template (used to create per-agent jobs dynamically via API)
resource "google_cloud_run_v2_job" "sandbox_template" {
  project  = var.project_id
  name     = "sandbox-template-${var.environment}"
  location = var.region

  template {
    template {
      service_account = google_service_account.sandbox_runner.email

      containers {
        image = var.default_sandbox_image

        resources {
          limits = {
            cpu    = var.sandbox_cpu
            memory = var.sandbox_memory
          }
        }

        # Environment variables for sandbox configuration
        env {
          name  = "SANDBOX_ENVIRONMENT"
          value = var.environment
        }

        # Timeout for sandbox execution
        env {
          name  = "SANDBOX_TIMEOUT"
          value = tostring(var.sandbox_timeout_seconds)
        }
      }

      # Maximum execution time
      timeout = "${var.sandbox_timeout_seconds}s"

      # Run in isolated VPC
      vpc_access {
        connector = var.vpc_connector_id
        egress    = "ALL_TRAFFIC"
      }

      # Execution environment with gVisor (default for Cloud Run)
      # Provides additional isolation for untrusted code
      execution_environment = "EXECUTION_ENVIRONMENT_GEN2"

      max_retries = 0 # No retries for sandboxes
    }

    parallelism = 1
    task_count  = 1
  }

  labels = var.labels

  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }
}

# Cloud Run service for persistent sandboxes (long-running notebooks/IDEs)
resource "google_cloud_run_v2_service" "persistent_sandbox" {
  project  = var.project_id
  name     = "sandbox-persistent-${var.environment}"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = google_service_account.sandbox_runner.email

    scaling {
      min_instance_count = 0
      max_instance_count = var.max_persistent_sandboxes
    }

    containers {
      image = var.persistent_sandbox_image != null ? var.persistent_sandbox_image : var.default_sandbox_image

      resources {
        limits = {
          cpu    = var.sandbox_cpu
          memory = var.sandbox_memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "SANDBOX_ENVIRONMENT"
        value = var.environment
      }

      env {
        name  = "SANDBOX_TYPE"
        value = "persistent"
      }

      ports {
        container_port = 8080
      }

      # Session affinity for stateful sandboxes
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 5
        timeout_seconds       = 3
        period_seconds        = 5
        failure_threshold     = 10
      }
    }

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "ALL_TRAFFIC"
    }

    # 15-minute timeout for idle sandboxes
    timeout = "900s"

    # Session affinity for stateful sandboxes
    session_affinity = true

    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"

    labels = var.labels
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  labels = var.labels
}

# Pub/Sub topic for sandbox events
resource "google_pubsub_topic" "sandbox_events" {
  project = var.project_id
  name    = "sandbox-events-${var.environment}"

  labels = var.labels

  message_retention_duration = "86600s" # 24 hours
}

# Pub/Sub subscription for sandbox event processing
resource "google_pubsub_subscription" "sandbox_events" {
  project = var.project_id
  name    = "sandbox-events-processor-${var.environment}"
  topic   = google_pubsub_topic.sandbox_events.name

  ack_deadline_seconds       = 60
  message_retention_duration = "86600s"

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = var.labels
}

# Grant main app access to create sandbox jobs
resource "google_cloud_run_v2_job_iam_member" "app_can_execute" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.sandbox_template.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${var.app_service_account}"
}

# Cloud Tasks queue for sandbox job scheduling
resource "google_cloud_tasks_queue" "sandbox_queue" {
  project  = var.project_id
  location = var.region
  name     = "sandbox-queue-${var.environment}"

  rate_limits {
    max_dispatches_per_second = var.max_sandbox_dispatches_per_second
    max_concurrent_dispatches = var.max_concurrent_sandboxes
  }

  retry_config {
    max_attempts = 3
    min_backoff  = "1s"
    max_backoff  = "60s"
  }

  stackdriver_logging_config {
    sampling_ratio = 1.0
  }
}

# IAM for app to enqueue sandbox tasks
resource "google_cloud_tasks_queue_iam_member" "app_can_enqueue" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_tasks_queue.sandbox_queue.name
  role     = "roles/cloudtasks.enqueuer"
  member   = "serviceAccount:${var.app_service_account}"
}
