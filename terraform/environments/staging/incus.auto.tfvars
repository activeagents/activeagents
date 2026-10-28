# The sandbox-staging Incus host (terraform/environments/sandbox-staging,
# project activeagents-staging, VM incus-host-staging). See
# docs/infrastructure/app-runtime.md (Connecting staging to its Incus host)
# before changing a value. The host's internal IP survives a stop/start
# (host.auto.tfvars there); only a recreated host gets a new one.
enable_incus_backend = true
incus_api_url        = "https://10.10.0.2:8443"
incus_secret_project = "756867485003"
incus_host_network   = "https://www.googleapis.com/compute/v1/projects/activeagents-staging/global/networks/sandbox-network"
incus_host_ranges    = ["10.10.0.0/24", "10.10.1.0/28", "10.10.2.0/28", "10.100.0.0/24"]

incus_app_runtime_enabled = true

# Claude Code signs in with each user's own subscription inside the sandbox
# (activeagent#578). Step 9 of the runbook: until Anthropic's Commercial
# Terms for hosting Claude Code and its confirmation of the design are
# recorded on #578, keep this on only while the operator is the only person
# who can open a checkout on staging.
claude_code_auth                 = "sandbox_login"
claude_code_hosted_login_enabled = true
