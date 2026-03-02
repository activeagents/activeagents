# frozen_string_literal: true

# Sandbox environment for ephemeral agent execution containers.
# This environment runs the same ActiveAgents application in a restricted mode
# suitable for free-tier users running sample agents.

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Sandbox mode inherits from production settings
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Sandbox-specific: use SQLite for isolated state (no shared DB)
  # Each container has its own ephemeral database

  # SSL handled by Cloud Run
  config.assume_ssl = true
  config.force_ssl = true

  # Structured JSON logging for Cloud Run observability
  config.log_tags = [ :request_id ]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"

  # Sandbox mode flags
  config.sandbox_mode = true
  config.sandbox_session_id = ENV.fetch("SANDBOX_SESSION_ID", nil)
  config.sandbox_owner_id = ENV.fetch("SANDBOX_OWNER_ID", nil)
  config.sandbox_max_runs = ENV.fetch("SANDBOX_MAX_RUNS", 10).to_i
  config.sandbox_timeout_seconds = ENV.fetch("SANDBOX_TIMEOUT", 300).to_i
  config.sandbox_max_tokens = ENV.fetch("SANDBOX_MAX_TOKENS", 50_000).to_i

  # Disable features not needed in sandbox
  config.active_storage.service = :local
  config.active_job.queue_adapter = :async # No Solid Queue in sandbox

  # Cache in memory only
  config.cache_store = :memory_store

  # No mailer in sandbox
  config.action_mailer.perform_deliveries = false

  # Sandbox containers should auto-terminate after inactivity
  config.sandbox_idle_timeout = ENV.fetch("SANDBOX_IDLE_TIMEOUT", 900).to_i # 15 minutes

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]
end
