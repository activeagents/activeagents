# Plans the root module against mock providers, so it runs without GCP
# credentials: terraform init -backend=false && terraform test

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_id  = "example-project"
  environment = "staging"
  image       = "us-central1-docker.pkg.dev/example-project/activeagents/activeagents:test"
}

run "defaults_pass_nothing_new_to_cloud_run" {
  command = plan

  assert {
    condition = toset(keys(local.cloud_run_secret_env_vars)) == toset([
      "DB_PASSWORD",
      "RAILS_MASTER_KEY",
      "RESEND_API_KEY",
      "RESEND_AUDIENCE_ID",
      "STRIPE_API_KEY",
      "STRIPE_WEBHOOK_SECRET",
    ])
    error_message = "With every flag off, Cloud Run must read only the secrets it read before."
  }

  assert {
    condition = toset(keys(local.cloud_run_env_vars)) == toset([
      "APP_HOST",
      "DB_HOST",
      "DB_NAME",
      "DB_USER",
      "INCUS_APP_RUNTIME_ENABLED",
      "MAILER_FROM_ADDRESS",
      "RAILS_ENV",
      "RAILS_LOG_TO_STDOUT",
      "RAILS_SERVE_STATIC_FILES",
      "RESEND_NEWSLETTER_AUDIENCE_ID",
      "SKIP_DB_PREPARE",
      "SOLID_QUEUE_IN_PUMA",
      "STRIPE_EXPECTED_ACCOUNT_ID",
      "STRIPE_REQUIRE_TEST_MODE",
    ])
    error_message = "With every flag off, Cloud Run must get only the plain variables it got before (staging adds its Stripe guard)."
  }

  assert {
    condition = alltrue([
      for key in [
        "github-app-client-id",
        "github-app-client-secret",
        "github-app-private-key",
        "github-app-webhook-secret",
        "active-record-encryption-primary-key",
        "active-record-encryption-deterministic-key",
        "active-record-encryption-key-derivation-salt",
      ] : module.secrets.secret_ids[key] == "activeagents-staging-${key}"
    ])
    error_message = "Every new secret must be declared, named activeagents-<env>-<key>."
  }

  assert {
    condition     = length(local.cloud_run_secret_volumes) == 0
    error_message = "With every flag off, Cloud Run must mount no secret volumes."
  }

  assert {
    condition     = output.incus_host == null && output.incus_host_peering == null
    error_message = "With every flag off, the app must get no Incus host and the VPC must peer with nothing."
  }
}

# -- Incus sandbox backend --------------------------------------------------

run "incus_backend_passes_the_host_and_mounts_its_credentials" {
  command = plan

  variables {
    enable_incus_backend = true
    incus_api_url        = "https://10.10.0.2:8443"
    incus_secret_project = "123456789012"
    incus_host_network   = "projects/activeagents-staging/global/networks/sandbox-network"
    incus_host_ranges    = ["10.10.0.0/24", "10.100.0.0/24"]
  }

  assert {
    condition = alltrue([
      local.cloud_run_env_vars["SANDBOX_BACKEND"] == "incus",
      local.cloud_run_env_vars["INCUS_HOST"] == "https://10.10.0.2:8443",
      local.cloud_run_env_vars["INCUS_PROJECT"] == "agent-sandboxes",
      local.cloud_run_env_vars["INCUS_CERT_PATH"] == "/secrets/incus-client-cert/client.crt",
      local.cloud_run_env_vars["INCUS_KEY_PATH"] == "/secrets/incus-client-key/client.key",
      local.cloud_run_env_vars["INCUS_SERVER_CA_PATH"] == "/secrets/incus-server-cert/server.crt",
    ])
    error_message = "The backend flag must pass SANDBOX_BACKEND, INCUS_HOST, INCUS_PROJECT and the mounted client certificate, key and server certificate paths."
  }

  assert {
    condition = local.cloud_run_secret_volumes == tomap({
      incus-client-cert = {
        secret     = "projects/123456789012/secrets/incus-client-cert-staging"
        mount_path = "/secrets/incus-client-cert"
        file       = "client.crt"
      }
      incus-client-key = {
        secret     = "projects/123456789012/secrets/incus-client-key-staging"
        mount_path = "/secrets/incus-client-key"
        file       = "client.key"
      }
      incus-server-cert = {
        secret     = "projects/123456789012/secrets/incus-server-cert-staging"
        mount_path = "/secrets/incus-server-cert"
        file       = "server.crt"
      }
    })
    error_message = "The client certificate, key and server certificate must be mounted from the secrets the host publishes, in the project that holds them."
  }

  assert {
    condition = alltrue([
      for name in ["INCUS_CERT_PATH", "INCUS_KEY_PATH", "INCUS_SERVER_CA_PATH"] :
      contains([for volume in values(local.cloud_run_secret_volumes) : "${volume.mount_path}/${volume.file}"], local.cloud_run_env_vars[name])
    ])
    error_message = "Every INCUS_*_PATH must name a file that is mounted."
  }

  assert {
    condition = toset(keys(local.cloud_run_secret_env_vars)) == toset([
      "DB_PASSWORD",
      "RAILS_MASTER_KEY",
      "RESEND_API_KEY",
      "RESEND_AUDIENCE_ID",
      "STRIPE_API_KEY",
      "STRIPE_WEBHOOK_SECRET",
    ])
    error_message = "The certificate and key are files, not secret variables."
  }

  assert {
    condition     = length([for name in keys(local.cloud_run_env_vars) : name if startswith(name, "CLAUDE_CODE_")]) == 0
    error_message = "The backend flag must not turn on Claude Code sign-in."
  }

  assert {
    condition     = output.incus_host == "https://10.10.0.2:8443" && output.incus_host_peering == "activeagents-staging-incus-host"
    error_message = "The backend flag must peer with the host's VPC when it is named."
  }
}

run "incus_secrets_default_to_this_project" {
  command = plan

  variables {
    enable_incus_backend = true
    incus_api_url        = "https://10.10.0.2:8443"
  }

  assert {
    condition = alltrue([
      local.cloud_run_secret_volumes["incus-client-cert"].secret == "incus-client-cert-staging",
      local.cloud_run_secret_volumes["incus-client-key"].secret == "incus-client-key-staging",
      local.cloud_run_secret_volumes["incus-server-cert"].secret == "incus-server-cert-staging",
    ])
    error_message = "Without incus_secret_project the secrets must be read from this project."
  }

  assert {
    condition     = output.incus_host_peering == null
    error_message = "Without incus_host_network the VPC must peer with nothing."
  }
}

run "incus_host_network_waits_for_the_backend_flag" {
  command = plan

  variables {
    incus_api_url      = "https://10.10.0.2:8443"
    incus_host_network = "projects/activeagents-staging/global/networks/sandbox-network"
    incus_host_ranges  = ["10.10.0.0/24", "10.100.0.0/24"]
  }

  assert {
    condition     = output.incus_host_peering == null && length(local.cloud_run_secret_volumes) == 0
    error_message = "Naming the host's VPC must change nothing while enable_incus_backend is off."
  }

  assert {
    condition     = length([for name in keys(local.cloud_run_env_vars) : name if startswith(name, "INCUS_") && name != "INCUS_APP_RUNTIME_ENABLED"]) == 0
    error_message = "The app must get no Incus host while enable_incus_backend is off."
  }
}

run "incus_backend_needs_its_url" {
  command = plan

  variables {
    enable_incus_backend = true
  }

  expect_failures = [output.incus_host]
}

run "incus_api_url_must_be_https" {
  command = plan

  variables {
    incus_api_url = "http://10.10.0.2:8443"
  }

  expect_failures = [var.incus_api_url]
}

run "incus_api_url_must_not_be_a_socket" {
  command = plan

  variables {
    incus_api_url = "unix:///var/lib/incus/unix.socket"
  }

  expect_failures = [var.incus_api_url]
}

run "incus_host_network_must_be_a_vpc" {
  command = plan

  variables {
    incus_host_network = "sandbox-network"
  }

  expect_failures = [var.incus_host_network]
}

# -- Claude Code in sandboxes -----------------------------------------------

run "claude_code_switches_pass_only_when_on" {
  command = plan

  variables {
    claude_code_auth                 = "sandbox_login"
    claude_code_hosted_login_enabled = true
  }

  assert {
    condition = alltrue([
      local.cloud_run_env_vars["CLAUDE_CODE_AUTH"] == "sandbox_login",
      local.cloud_run_env_vars["CLAUDE_CODE_HOSTED_LOGIN_ENABLED"] == "true",
    ])
    error_message = "Each Claude Code switch must reach the app once it is on."
  }

  assert {
    condition     = !contains(keys(local.cloud_run_env_vars), "SANDBOX_BACKEND") && length(local.cloud_run_secret_volumes) == 0
    error_message = "The Claude Code switches must not point the app at an Incus host."
  }
}

run "claude_code_auth_is_api_key_or_sandbox_login" {
  command = plan

  variables {
    claude_code_auth = "oauth"
  }

  expect_failures = [var.claude_code_auth]
}

# -- The cloud-run module's secret volumes ----------------------------------

run "cloud_run_module_mounts_nothing_by_default" {
  command = plan

  module {
    source = "./modules/cloud-run"
  }

  variables {
    region               = "us-central1"
    service_account      = "activeagents-staging@example-project.iam.gserviceaccount.com"
    vpc_connector_id     = "projects/example-project/locations/us-central1/connectors/activeagents-staging"
    cloud_sql_connection = "example-project:us-central1:activeagents-staging"
  }

  assert {
    condition = alltrue([
      [for volume in google_cloud_run_v2_service.main.template[0].volumes : volume.name] == ["cloudsql"],
      [for mount in google_cloud_run_v2_service.main.template[0].containers[0].volume_mounts : mount.name] == ["cloudsql"],
      [for volume in google_cloud_run_v2_job.migrate.template[0].template[0].volumes : volume.name] == ["cloudsql"],
      [for mount in google_cloud_run_v2_job.migrate.template[0].template[0].containers[0].volume_mounts : mount.name] == ["cloudsql"],
    ])
    error_message = "Without secret_volumes the service and the job must mount only Cloud SQL, as before."
  }
}

run "cloud_run_module_mounts_secret_volumes_in_the_service_and_job" {
  command = plan

  module {
    source = "./modules/cloud-run"
  }

  variables {
    region               = "us-central1"
    service_account      = "activeagents-staging@example-project.iam.gserviceaccount.com"
    vpc_connector_id     = "projects/example-project/locations/us-central1/connectors/activeagents-staging"
    cloud_sql_connection = "example-project:us-central1:activeagents-staging"
    secret_volumes = {
      incus-client-cert = {
        secret     = "projects/123456789012/secrets/incus-client-cert-staging"
        mount_path = "/secrets/incus-client-cert"
        file       = "client.crt"
      }
    }
  }

  assert {
    condition = alltrue([
      for volumes in [
        google_cloud_run_v2_service.main.template[0].volumes,
        google_cloud_run_v2_job.migrate.template[0].template[0].volumes,
      ] :
      [
        for volume in volumes : {
          secret  = volume.secret[0].secret
          path    = volume.secret[0].items[0].path
          version = volume.secret[0].items[0].version
        } if volume.name == "incus-client-cert"
        ] == [{
          secret  = "projects/123456789012/secrets/incus-client-cert-staging"
          path    = "client.crt"
          version = "latest"
      }]
    ])
    error_message = "The service and the job must each mount the secret's latest version under the file name given."
  }

  assert {
    condition = alltrue([
      for mounts in [
        google_cloud_run_v2_service.main.template[0].containers[0].volume_mounts,
        google_cloud_run_v2_job.migrate.template[0].template[0].containers[0].volume_mounts,
      ] :
      [for mount in mounts : "${mount.name}:${mount.mount_path}"] == ["cloudsql:/cloudsql", "incus-client-cert:/secrets/incus-client-cert"]
    ])
    error_message = "The service and the job must each mount the volume at its mount_path, after Cloud SQL."
  }
}

# -- The networking module's peering with an Incus host ---------------------

run "networking_module_peers_with_nothing_by_default" {
  command = plan

  module {
    source = "./modules/networking"
  }

  variables {
    region = "us-central1"
  }

  assert {
    condition     = length(google_compute_network_peering.incus_host) == 0 && length(google_compute_firewall.deny_from_incus_host) == 0
    error_message = "Without incus_host_network the VPC must peer with nothing and add no firewall rule."
  }

  assert {
    condition     = output.vpc_connector_cidr == "10.8.0.0/28"
    error_message = "The connector range is what the Incus host's firewall admits; changing it needs the host's platform_egress_ranges changed too."
  }
}

run "networking_module_peers_with_the_incus_host" {
  command = plan

  module {
    source = "./modules/networking"
  }

  variables {
    region             = "us-central1"
    incus_host_network = "projects/activeagents-staging/global/networks/sandbox-network"
    incus_host_ranges  = ["10.10.0.0/24", "10.100.0.0/24"]
  }

  assert {
    condition = alltrue([
      google_compute_network_peering.incus_host[0].peer_network == "projects/activeagents-staging/global/networks/sandbox-network",
      google_compute_network_peering.incus_host[0].import_custom_routes == true,
      google_compute_network_peering.incus_host[0].export_custom_routes == false,
    ])
    error_message = "The VPC must peer with the host's VPC, import its route to the bridge and export nothing of its own."
  }

  # allow_internal sets no priority, so GCP gives it 1000.
  assert {
    condition = alltrue([
      google_compute_firewall.deny_from_incus_host[0].direction == "INGRESS",
      google_compute_firewall.deny_from_incus_host[0].priority < coalesce(google_compute_firewall.allow_internal.priority, 1000),
      google_compute_firewall.deny_from_incus_host[0].source_ranges == toset(["10.10.0.0/24", "10.100.0.0/24"]),
      [for rule in google_compute_firewall.deny_from_incus_host[0].deny : rule.protocol] == ["all"],
    ])
    error_message = "Connections from the host's ranges must be denied ahead of allow_internal."
  }
}

run "recordings_bucket_is_private_and_scoped" {
  command = plan

  assert {
    condition     = google_storage_bucket.recordings.name == "example-project-recordings-staging"
    error_message = "The bucket name must carry the project and the environment."
  }

  assert {
    condition     = google_storage_bucket.recordings.uniform_bucket_level_access && google_storage_bucket.recordings.public_access_prevention == "enforced"
    error_message = "The recordings bucket must use uniform access and enforce public access prevention."
  }

  assert {
    condition = toset([
      for binding in data.google_iam_policy.recordings.binding : binding.role
    ]) == toset(["roles/storage.objectAdmin", "roles/storage.objectViewer"])
    error_message = "The bucket policy must hold only the app's objectAdmin and the signer's objectViewer bindings."
  }

  assert {
    condition     = google_storage_bucket_iam_policy.recordings.bucket == "example-project-recordings-staging"
    error_message = "The authoritative policy must be set on the recordings bucket."
  }

  assert {
    condition     = google_service_account_iam_member.recordings_signer_token_creator.role == "roles/iam.serviceAccountTokenCreator"
    error_message = "The app must be able to sign as the signer through the IAM Credentials API."
  }

  assert {
    condition     = contains(keys(google_project_service.apis), "storage.googleapis.com") && contains(keys(google_project_service.apis), "iamcredentials.googleapis.com")
    error_message = "Storage and IAM Credentials APIs must be enabled."
  }
}

run "flags_pass_their_variables" {
  command = plan

  variables {
    enable_github_sign_in                = true
    enable_github_app                    = true
    github_app_id                        = "123456"
    github_app_slug                      = "activeagents-staging"
    enable_active_record_encryption_keys = true
    enable_recordings_storage            = true
  }

  assert {
    condition = alltrue([
      local.cloud_run_secret_env_vars["GITHUB_APP_CLIENT_ID"] == "activeagents-staging-github-app-client-id",
      local.cloud_run_secret_env_vars["GITHUB_APP_CLIENT_SECRET"] == "activeagents-staging-github-app-client-secret",
      local.cloud_run_secret_env_vars["GITHUB_APP_PRIVATE_KEY"] == "activeagents-staging-github-app-private-key",
      local.cloud_run_secret_env_vars["GITHUB_APP_WEBHOOK_SECRET"] == "activeagents-staging-github-app-webhook-secret",
      local.cloud_run_secret_env_vars["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] == "activeagents-staging-active-record-encryption-primary-key",
      local.cloud_run_secret_env_vars["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] == "activeagents-staging-active-record-encryption-deterministic-key",
      local.cloud_run_secret_env_vars["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] == "activeagents-staging-active-record-encryption-key-derivation-salt",
    ])
    error_message = "Each flag must map its secrets to the variable names the app reads."
  }

  assert {
    condition = alltrue([
      local.cloud_run_env_vars["GITHUB_APP_ID"] == "123456",
      local.cloud_run_env_vars["GITHUB_APP_SLUG"] == "activeagents-staging",
      local.cloud_run_env_vars["RECORDINGS_BUCKET"] == "example-project-recordings-staging",
    ])
    error_message = "The App ID, slug and bucket must reach the app as plain variables."
  }

  assert {
    condition     = output.github_app_install_url == "https://github.com/apps/activeagents-staging/installations/new"
    error_message = "The install URL must use the App's slug."
  }
}

run "encryption_keys_stay_off_unless_asked" {
  command = plan

  variables {
    enable_github_app = true
    github_app_id     = "123456"
    github_app_slug   = "activeagents-staging"
  }

  assert {
    condition     = length([for name in keys(local.cloud_run_secret_env_vars) : name if startswith(name, "ACTIVE_RECORD_ENCRYPTION_")]) == 0
    error_message = "Turning on the GitHub App must not pass the encryption keys."
  }
}

run "github_app_needs_its_id_and_slug" {
  command = plan

  variables {
    enable_github_app = true
  }

  expect_failures = [output.github_app_install_url]
}

run "github_app_id_must_be_numeric" {
  command = plan

  variables {
    github_app_id = "Iv1.abc123"
  }

  expect_failures = [var.github_app_id]
}
