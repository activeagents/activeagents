# Incus Host VM on GCP
#
# Creates a Compute Engine VM to run Incus for sandbox containers.
# This provides a cloud-agnostic container runtime on GCP infrastructure.
#
# Usage:
#   module "incus_host" {
#     source       = "../../modules/incus-host"
#     project_id   = "your-project"
#     environment  = "staging"
#     network_id   = google_compute_network.main.id
#     subnet_id    = google_compute_subnetwork.main.id
#   }

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

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
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
  description = "Subnet ID"
  type        = string
}

variable "machine_type" {
  description = "VM machine type"
  type        = string
  default     = "n2-standard-8"  # 8 vCPU, 32GB RAM
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 200
}

variable "enable_gpu" {
  description = "Enable GPU support"
  type        = bool
  default     = false
}

variable "gpu_type" {
  description = "GPU accelerator type (if enabled)"
  type        = string
  default     = "nvidia-tesla-t4"
}

variable "gpu_count" {
  description = "Number of GPUs (if enabled)"
  type        = number
  default     = 1
}

variable "allowed_source_ranges" {
  description = "IP ranges allowed to access Incus API"
  type        = list(string)
  default     = []  # Empty = only Cloud Run via VPC connector
}

# -----------------------------------------------------------------------------
# Service Account
# -----------------------------------------------------------------------------

resource "google_service_account" "incus_host" {
  account_id   = "incus-host-${var.environment}"
  display_name = "Incus Host Service Account"
  project      = var.project_id
}

# Allow access to Container Registry / Artifact Registry
resource "google_project_iam_member" "incus_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.incus_host.email}"
}

# Allow access to Secret Manager
resource "google_project_iam_member" "incus_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.incus_host.email}"
}

# Allow logging
resource "google_project_iam_member" "incus_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.incus_host.email}"
}

# Allow metrics
resource "google_project_iam_member" "incus_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.incus_host.email}"
}

# -----------------------------------------------------------------------------
# Firewall Rules
# -----------------------------------------------------------------------------

resource "google_compute_firewall" "incus_api" {
  name    = "incus-api-${var.environment}"
  network = var.network_id
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["8443"]  # Incus API
  }

  source_ranges = length(var.allowed_source_ranges) > 0 ? var.allowed_source_ranges : ["10.0.0.0/8"]
  target_tags   = ["incus-host"]
}

resource "google_compute_firewall" "incus_health" {
  name    = "incus-health-${var.environment}"
  network = var.network_id
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]  # Health checks
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]  # GCP health checkers
  target_tags   = ["incus-host"]
}

# -----------------------------------------------------------------------------
# Compute Instance
# -----------------------------------------------------------------------------

resource "google_compute_instance" "incus_host" {
  name         = "incus-host-${var.environment}"
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  tags = ["incus-host", "sandbox-host"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.disk_size_gb
      type  = "pd-ssd"
    }
  }

  # GPU configuration (optional)
  dynamic "guest_accelerator" {
    for_each = var.enable_gpu ? [1] : []
    content {
      type  = var.gpu_type
      count = var.gpu_count
    }
  }

  # GPU requires on-host maintenance disabled
  scheduling {
    on_host_maintenance = var.enable_gpu ? "TERMINATE" : "MIGRATE"
    automatic_restart   = true
    preemptible         = false
  }

  network_interface {
    subnetwork = var.subnet_id

    # External IP for initial setup (can be removed later)
    access_config {
      // Ephemeral IP
    }
  }

  service_account {
    email  = google_service_account.incus_host.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = <<-SCRIPT
    #!/bin/bash
    set -euo pipefail

    # Log everything
    exec > >(tee /var/log/startup-script.log) 2>&1
    echo "Starting Incus host setup at $(date)"

    # Install dependencies
    apt-get update
    apt-get install -y curl wget apt-transport-https ca-certificates gnupg

    # Add Zabbly repository for Incus
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.zabbly.com/key.asc | gpg --dearmor -o /etc/apt/keyrings/zabbly.gpg

    cat > /etc/apt/sources.list.d/zabbly-incus-stable.list << EOF
    deb [signed-by=/etc/apt/keyrings/zabbly.gpg] https://pkgs.zabbly.com/incus/stable $(lsb_release -cs) main
    EOF

    apt-get update
    apt-get install -y incus incus-tools

    # Initialize Incus with preseed config
    cat << 'PRESEED' | incus admin init --preseed
    config:
      core.https_address: "[::]:8443"
      images.auto_update_interval: 6

    networks:
      - name: incusbr0
        type: bridge
        config:
          ipv4.address: 10.100.0.1/24
          ipv4.nat: "true"
          ipv4.dhcp.ranges: 10.100.0.10-10.100.0.254
          ipv6.address: none

    storage_pools:
      - name: default
        driver: dir
        config:
          source: /var/lib/incus/storage-pools/default

    profiles:
      - name: default
        config: {}
        devices:
          eth0:
            name: eth0
            network: incusbr0
            type: nic
          root:
            path: /
            pool: default
            type: disk
            size: 20GB
    PRESEED

    # Create sandbox project
    incus project create agent-sandboxes \
      -c features.images=true \
      -c features.profiles=true

    # Create restricted sandbox profile
    incus project switch agent-sandboxes
    incus profile create sandbox-restricted

    incus profile set sandbox-restricted security.nesting=false
    incus profile set sandbox-restricted security.privileged=false
    incus profile set sandbox-restricted security.idmap.isolated=true
    incus profile set sandbox-restricted limits.cpu=2
    incus profile set sandbox-restricted limits.memory=2GB
    incus profile set sandbox-restricted limits.processes=500

    incus profile device add sandbox-restricted eth0 nic network=incusbr0 name=eth0
    incus profile device add sandbox-restricted root disk pool=default path=/ size=10GB

    incus project switch default

    # Setup GPU passthrough if enabled
    %{if var.enable_gpu}
    # Install NVIDIA drivers
    apt-get install -y nvidia-driver-535 nvidia-container-toolkit

    # Configure Incus for GPU
    cat > /etc/incus/gpu.conf << 'GPUCONF'
    nvidia.runtime = true
    GPUCONF
    %{endif}

    # Generate client certificate for Rails app
    mkdir -p /etc/incus/certs
    openssl req -x509 -newkey rsa:4096 -keyout /etc/incus/certs/client.key \
      -out /etc/incus/certs/client.crt -days 365 -nodes \
      -subj "/CN=activeagents-client"

    # Add client cert to Incus trust store
    incus config trust add /etc/incus/certs/client.crt --name activeagents

    # Store certs in Secret Manager
    gcloud secrets create incus-client-cert-${var.environment} \
      --data-file=/etc/incus/certs/client.crt \
      --project=${var.project_id} 2>/dev/null || \
    gcloud secrets versions add incus-client-cert-${var.environment} \
      --data-file=/etc/incus/certs/client.crt \
      --project=${var.project_id}

    gcloud secrets create incus-client-key-${var.environment} \
      --data-file=/etc/incus/certs/client.key \
      --project=${var.project_id} 2>/dev/null || \
    gcloud secrets versions add incus-client-key-${var.environment} \
      --data-file=/etc/incus/certs/client.key \
      --project=${var.project_id}

    # Create cleanup cron job
    cat > /etc/cron.d/incus-sandbox-cleanup << 'CRON'
    */5 * * * * root /usr/local/bin/cleanup-sandboxes.sh
    CRON

    cat > /usr/local/bin/cleanup-sandboxes.sh << 'CLEANUP'
    #!/bin/bash
    PROJECT="agent-sandboxes"
    MAX_AGE=900

    incus project switch "$PROJECT" 2>/dev/null || exit 0

    for container in $(incus list --format csv -c n 2>/dev/null | grep "^sandbox-"); do
      created=$(incus config get "$container" user.created_at 2>/dev/null || echo "")
      if [[ -n "$created" ]]; then
        created_ts=$(date -d "$created" +%s 2>/dev/null || echo 0)
        now_ts=$(date +%s)
        age=$((now_ts - created_ts))

        if [[ $age -gt $MAX_AGE ]]; then
          incus stop "$container" --force 2>/dev/null
          incus delete "$container" 2>/dev/null
          logger "Cleaned up expired sandbox: $container (age: $age seconds)"
        fi
      fi
    done

    incus project switch default 2>/dev/null
    CLEANUP

    chmod +x /usr/local/bin/cleanup-sandboxes.sh

    # Enable and start services
    systemctl enable incus
    systemctl restart incus

    echo "Incus host setup complete at $(date)"
  SCRIPT

  labels = {
    environment = var.environment
    service     = "incus-sandboxes"
    managed_by  = "terraform"
  }

  lifecycle {
    ignore_changes = [
      metadata_startup_script,  # Don't recreate for script changes
    ]
  }
}

# -----------------------------------------------------------------------------
# Health Check
# -----------------------------------------------------------------------------

resource "google_compute_health_check" "incus" {
  name    = "incus-health-${var.environment}"
  project = var.project_id

  tcp_health_check {
    port = 8443
  }

  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3
}

# -----------------------------------------------------------------------------
# Instance Group (for load balancing if needed)
# -----------------------------------------------------------------------------

resource "google_compute_instance_group" "incus" {
  name    = "incus-group-${var.environment}"
  zone    = var.zone
  project = var.project_id

  instances = [google_compute_instance.incus_host.id]

  named_port {
    name = "incus-api"
    port = 8443
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "instance_name" {
  description = "Incus host instance name"
  value       = google_compute_instance.incus_host.name
}

output "instance_ip" {
  description = "Incus host internal IP"
  value       = google_compute_instance.incus_host.network_interface[0].network_ip
}

output "instance_external_ip" {
  description = "Incus host external IP (for initial setup)"
  value       = google_compute_instance.incus_host.network_interface[0].access_config[0].nat_ip
}

output "incus_api_url" {
  description = "Incus API URL (internal)"
  value       = "https://${google_compute_instance.incus_host.network_interface[0].network_ip}:8443"
}

output "service_account_email" {
  description = "Incus host service account"
  value       = google_service_account.incus_host.email
}

output "client_cert_secret" {
  description = "Secret Manager secret for client certificate"
  value       = "incus-client-cert-${var.environment}"
}

output "client_key_secret" {
  description = "Secret Manager secret for client key"
  value       = "incus-client-key-${var.environment}"
}
