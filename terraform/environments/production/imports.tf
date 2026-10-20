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

import {
  to = module.activeagents.module.secrets.google_secret_manager_secret.secrets["turnstile-secret-key"]
  id = "projects/${var.project_id}/secrets/activeagents-production-turnstile-secret-key"
}

# The serverless NEG and the backend service of the production load balancer
# existed before the first apply of infra/production-full-stack (#181), from an
# earlier bring-up that left no state, so that apply failed with a 409 on the
# NEG. Both match what the load-balancer module declares (the NEG points at
# the activeagents-production service; the backend uses that NEG).

import {
  to = module.activeagents.module.load_balancer[0].google_compute_region_network_endpoint_group.serverless_neg
  id = "projects/${var.project_id}/regions/${var.region}/networkEndpointGroups/activeagents-production-neg"
}

import {
  to = module.activeagents.module.load_balancer[0].google_compute_backend_service.default
  id = "projects/${var.project_id}/global/backendServices/activeagents-production-backend"
}
