# Secret Manager module for ActiveAgents
# Creates secrets (values must be set manually or via CI/CD)

resource "google_secret_manager_secret" "secrets" {
  for_each = var.secrets

  project   = var.project_id
  secret_id = "activeagents-${var.environment}-${each.key}"

  labels = merge(var.labels, {
    secret_name = each.key
  })

  replication {
    auto {}
  }
}

# IAM binding for service accounts to access secrets
resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = var.accessor_service_accounts != null ? {
    for pair in setproduct(keys(var.secrets), var.accessor_service_accounts) :
    "${pair[0]}-${pair[1]}" => {
      secret          = pair[0]
      service_account = pair[1]
    }
  } : {}

  project   = var.project_id
  secret_id = google_secret_manager_secret.secrets[each.value.secret].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value.service_account}"
}
