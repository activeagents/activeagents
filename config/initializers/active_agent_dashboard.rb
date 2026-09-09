# frozen_string_literal: true

# Action Agent dashboard configuration for the hosted platform.
#
# The hosted platform runs the dashboard/telemetry stack in multi-tenant mode:
# traces belong to Accounts and are ingested through
# ActionAgent::Api::TracesController (see routes for POST /v1/traces) and
# ActionAgent::ProcessTelemetryTracesJob.
#
# Self-hosted apps get the same pipeline in local mode via
# `rails generate action_agent:install` — the hosted app is the multi-tenant
# deployment of that same implementation.
#
# The dashboard moved out of the activeagent gem into actionagent in 1.2.0.
# ActiveAgent::Dashboard still resolves here through ActionAgent::Compatibility,
# but only with a deprecation warning, so this configures ActionAgent directly.
ActionAgent.configure do |config|
  # Multi-tenant mode: traces belong to accounts, ingest is authenticated
  # with Account#telemetry_api_key (Bearer token).
  config.multi_tenant = true
  config.account_class = "Account"
  config.user_class = "User"

  # Resolvers, not current_user_method/current_account_method.
  #
  # 1.2.0 gave the engine its own controller base class, so this app's
  # `current_user` is not on it. The named-method form is also actively
  # unsafe here: ApplicationController#resolve_actor returns nil when
  # method_name == the accessor it is resolving, which is exactly what
  # `current_user_method = :current_user` asks for. That used to recurse into
  # SystemStackError; it now degrades to nil, and an unresolved owner scopes
  # to nothing rather than to everything — every account's dashboard would
  # render empty, with no error anywhere to explain it.
  #
  # Reading the signed cookie directly is what makes these work. `Current`
  # is populated by the host's own before_action (see
  # Authentication#resume_session), which never runs for engine requests, so
  # a resolver that consults Current.session would find nothing.
  config.current_user_resolver = ->(controller) {
    session_id = controller.send(:cookies).signed[:session_id]
    Session.find_by(id: session_id)&.user if session_id
  }

  config.current_account_resolver = ->(controller) {
    session_id = controller.send(:cookies).signed[:session_id]
    Session.find_by(id: session_id)&.user&.primary_account if session_id
  }

  # Use the hosted TelemetryTrace model (subclass of ActionAgent::TelemetryTrace
  # pointed at our telemetry_traces table).
  config.trace_model_class = "TelemetryTrace"
end
