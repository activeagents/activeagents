# frozen_string_literal: true

# ActiveAgent Dashboard configuration for the hosted platform.
#
# The hosted platform runs the activeagent gem's dashboard/telemetry stack in
# multi-tenant mode: traces are attributed to Accounts and ingested through
# the gem's ActiveAgent::Dashboard::Api::TracesController (see routes for
# POST /v1/traces) and ActiveAgent::ProcessTelemetryTracesJob.
#
# Self-hosted apps get the same pipeline in local mode via the gem's
# `active_agent:dashboard:install` generator — the hosted app is the
# multi-tenant deployment of that same implementation.
ActiveAgent::Dashboard.configure do |config|
  # Multi-tenant mode: traces belong to accounts, ingest is authenticated
  # with Account#telemetry_api_key (Bearer token).
  config.multi_tenant = true
  config.account_class = "Account"
  config.user_class = "User"
  config.current_account_method = :current_account
  config.current_user_method = :current_user

  # Use the hosted TelemetryTrace model (subclass of the gem's
  # ActiveAgent::TelemetryTrace pointed at our telemetry_traces table).
  config.trace_model_class = "TelemetryTrace"
end

# WORKAROUND (remove after activeagents/activeagent#344 ships): the engine
# in gem <= 1.0.3 never registers its app/ directory on host load paths, so
# the pieces the platform builds on are required explicitly. With the fixed
# engine these requires are harmless no-ops (verified: full suite green on
# the patched gem with these lines deleted).
engine_app = ActiveAgent::Dashboard::Engine.root.join("app")
require engine_app.join("models/active_agent/telemetry_trace").to_s
require engine_app.join("jobs/active_agent/process_telemetry_traces_job").to_s
require engine_app.join("controllers/active_agent/dashboard/api/traces_controller").to_s
