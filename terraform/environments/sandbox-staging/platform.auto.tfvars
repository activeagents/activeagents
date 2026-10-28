# Serve the staging platform's Cloud Run (project active-agents-platform):
# peer with its VPC, route the container bridge to the host, and admit only
# its VPC connector's range on the Incus API (8443) and the containers' app
# port (8080). Values from terraform/environments/staging's vpc_self_link and
# vpc_connector_cidr outputs. See docs/infrastructure/app-runtime.md
# (Connecting staging to its Incus host). Committed so a push apply from
# deploy-sandbox-staging.yml cannot drop the peering, the route or the rules.
platform_network       = "projects/active-agents-platform/global/networks/activeagents-staging"
platform_egress_ranges = ["10.8.0.0/28"]
