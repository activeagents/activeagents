# frozen_string_literal: true

# Configuration for ActiveAgent::Dashboard (telemetry engine from activeagent gem)
#
# This enables multi-tenant mode for activeagents.ai platform, where each
# account has their own telemetry traces associated via API key.
#
# See the activeagent gem for full documentation:
# https://github.com/activeagents/activeagent
#
ActiveAgent::Dashboard.configure do |config|
  # Enable multi-tenant mode for the activeagents.ai platform
  config.multi_tenant = true

  # Account model for tenant association
  config.account_class = "Account"

  # Method to get current account in controllers
  config.current_account_method = :current_account

  # Use the host app's TelemetryTrace model (extends the gem's model)
  config.trace_model_class = "TelemetryTrace"

  # Use Inertia/React frontend for the dashboard
  config.use_inertia = true

  # Use the host app's layout
  config.layout = "application"

  # Authentication - require logged in user
  config.authentication_method = ->(controller) {
    controller.require_authentication
  }
end
