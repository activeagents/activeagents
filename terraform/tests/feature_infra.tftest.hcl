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
