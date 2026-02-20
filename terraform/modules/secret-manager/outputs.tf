output "secret_ids" {
  description = "Map of secret names to their Secret Manager IDs"
  value = {
    for key, secret in google_secret_manager_secret.secrets :
    key => secret.secret_id
  }
}

output "secret_names" {
  description = "Map of secret names to their full resource names"
  value = {
    for key, secret in google_secret_manager_secret.secrets :
    key => secret.name
  }
}
