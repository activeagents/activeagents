# Adopts the Resend secrets, which exist in Secret Manager but not in this
# environment's state. Without these blocks, apply fails with a 409 on create.
# Once they are in state, each block is a no-op.

import {
  to = module.activeagents.module.secrets.google_secret_manager_secret.secrets["resend-api-key"]
  id = "projects/${var.project_id}/secrets/activeagents-production-resend-api-key"
}

import {
  to = module.activeagents.module.secrets.google_secret_manager_secret.secrets["resend-audience-id"]
  id = "projects/${var.project_id}/secrets/activeagents-production-resend-audience-id"
}
