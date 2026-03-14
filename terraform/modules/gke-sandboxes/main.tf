# GKE Cluster for Agent Sandbox Sessions
#
# This module creates a GKE Autopilot cluster for running ephemeral
# agent sessions with full Kubernetes control.
#
# Benefits over Cloud Run:
# - Pod-level isolation with gVisor
# - Custom resource limits per agent type
# - Persistent volumes for session state
# - Network policies for isolation
# - Custom scheduling and affinity rules

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
}

variable "network_id" {
  description = "VPC network ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for GKE nodes"
  type        = string
}

variable "sandbox_image" {
  description = "Container image for sandbox pods"
  type        = string
}

variable "max_pods_per_node" {
  description = "Maximum pods per node"
  type        = number
  default     = 32
}

# -----------------------------------------------------------------------------
# GKE Autopilot Cluster
# -----------------------------------------------------------------------------

resource "google_container_cluster" "sandboxes" {
  name     = "agent-sandboxes-${var.environment}"
  location = var.region
  project  = var.project_id

  # Autopilot mode - Google manages nodes, we just deploy pods
  enable_autopilot = true

  # Network configuration
  network    = var.network_id
  subnetwork = var.subnet_id

  # Private cluster - no public IPs on nodes
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # IP allocation for pods and services
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "/16"
    services_ipv4_cidr_block = "/22"
  }

  # Workload Identity for secure GCP access
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Security settings
  release_channel {
    channel = "REGULAR"
  }

  # Enable GKE Sandbox (gVisor) for untrusted workloads
  # Note: Autopilot automatically enables this for sandbox-mode pods
}

# -----------------------------------------------------------------------------
# Namespace for Sandboxes
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "sandboxes" {
  metadata {
    name = "agent-sandboxes"

    labels = {
      "app.kubernetes.io/name"       = "agent-sandboxes"
      "app.kubernetes.io/managed-by" = "terraform"
      environment                     = var.environment
    }

    annotations = {
      # Enable pod security standards
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }

  depends_on = [google_container_cluster.sandboxes]
}

# -----------------------------------------------------------------------------
# Resource Quotas
# -----------------------------------------------------------------------------

resource "kubernetes_resource_quota" "sandboxes" {
  metadata {
    name      = "sandbox-quota"
    namespace = kubernetes_namespace.sandboxes.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = "100"      # 100 CPU cores total
      "requests.memory" = "200Gi"    # 200GB memory total
      "limits.cpu"      = "200"      # 200 CPU cores limit
      "limits.memory"   = "400Gi"    # 400GB memory limit
      "pods"            = "500"      # Max 500 concurrent sandboxes
      "services"        = "100"
    }
  }
}

# -----------------------------------------------------------------------------
# Network Policy - Isolate sandboxes from each other
# -----------------------------------------------------------------------------

resource "kubernetes_network_policy" "sandbox_isolation" {
  metadata {
    name      = "sandbox-isolation"
    namespace = kubernetes_namespace.sandboxes.metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/component" = "sandbox"
      }
    }

    # Deny all ingress by default
    ingress = []

    # Allow egress to internet only (not other pods)
    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
          except = [
            "10.0.0.0/8",      # Private networks
            "172.16.0.0/12",
            "192.168.0.0/16"
          ]
        }
      }
    }

    # Allow egress to DNS
    egress {
      ports {
        port     = 53
        protocol = "UDP"
      }
      ports {
        port     = 53
        protocol = "TCP"
      }
    }

    policy_types = ["Ingress", "Egress"]
  }
}

# -----------------------------------------------------------------------------
# Service Account for Sandbox Pods
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "sandbox_runner" {
  metadata {
    name      = "sandbox-runner"
    namespace = kubernetes_namespace.sandboxes.metadata[0].name

    annotations = {
      # Workload Identity binding
      "iam.gke.io/gcp-service-account" = google_service_account.sandbox_runner.email
    }
  }
}

resource "google_service_account" "sandbox_runner" {
  account_id   = "sandbox-runner-${var.environment}"
  display_name = "Sandbox Runner Service Account"
  project      = var.project_id
}

resource "google_service_account_iam_member" "sandbox_workload_identity" {
  service_account_id = google_service_account.sandbox_runner.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[agent-sandboxes/sandbox-runner]"
}

# Grant access to Secret Manager
resource "google_project_iam_member" "sandbox_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.sandbox_runner.email}"
}

# -----------------------------------------------------------------------------
# Pod Template for Sandbox Sessions
# -----------------------------------------------------------------------------

# This is a template - actual pods are created dynamically by the Rails app
# via the Kubernetes API

resource "kubernetes_config_map" "sandbox_pod_template" {
  metadata {
    name      = "sandbox-pod-template"
    namespace = kubernetes_namespace.sandboxes.metadata[0].name
  }

  data = {
    "pod-template.yaml" = yamlencode({
      apiVersion = "v1"
      kind       = "Pod"
      metadata = {
        generateName = "sandbox-"
        labels = {
          "app.kubernetes.io/name"      = "agent-sandbox"
          "app.kubernetes.io/component" = "sandbox"
        }
        annotations = {
          # Enable gVisor sandbox runtime
          "sandbox.gke.io/runtime" = "gvisor"
        }
      }
      spec = {
        serviceAccountName = "sandbox-runner"

        # Auto-terminate after 15 minutes
        activeDeadlineSeconds = 900

        # Don't restart on failure
        restartPolicy = "Never"

        # Security context
        securityContext = {
          runAsNonRoot = true
          runAsUser    = 1000
          runAsGroup   = 1000
          fsGroup      = 1000
          seccompProfile = {
            type = "RuntimeDefault"
          }
        }

        containers = [{
          name  = "sandbox"
          image = var.sandbox_image

          resources = {
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "2"
              memory = "2Gi"
            }
          }

          # Environment variables (placeholders - set at runtime)
          env = [
            { name = "RAILS_ENV", value = "sandbox" },
            { name = "SANDBOX_MODE", value = "true" },
            { name = "SANDBOX_SESSION_ID", value = "" },      # Set at runtime
            { name = "SANDBOX_OWNER_ID", value = "" },        # Set at runtime
            { name = "PLAYWRIGHT_BROWSERS_PATH", value = "/usr/bin" }
          ]

          # Security
          securityContext = {
            allowPrivilegeEscalation = false
            readOnlyRootFilesystem   = false  # Playwright needs write access
            capabilities = {
              drop = ["ALL"]
            }
          }

          # Health check
          readinessProbe = {
            httpGet = {
              path = "/up"
              port = 8080
            }
            initialDelaySeconds = 5
            periodSeconds       = 5
          }

          ports = [{
            containerPort = 8080
            protocol      = "TCP"
          }]
        }]

        # Tolerations for Autopilot sandbox nodes
        tolerations = [{
          key      = "sandbox.gke.io/runtime"
          operator = "Equal"
          value    = "gvisor"
          effect   = "NoSchedule"
        }]
      }
    })
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.sandboxes.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.sandboxes.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.sandboxes.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "namespace" {
  description = "Kubernetes namespace for sandboxes"
  value       = kubernetes_namespace.sandboxes.metadata[0].name
}

output "service_account_email" {
  description = "GCP service account for sandbox pods"
  value       = google_service_account.sandbox_runner.email
}
