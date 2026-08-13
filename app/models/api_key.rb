# frozen_string_literal: true

# Moved to the activeagent gem's dashboard engine, which this app mounts and
# configures (config/initializers/active_agent_dashboard.rb). The name stays
# so the rest of the app — and anything referring to it from outside — keeps
# working.
ApiKey = ActiveAgent::Dashboard::ApiKey
