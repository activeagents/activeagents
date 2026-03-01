# frozen_string_literal: true

# Sandbox mode configuration for ephemeral agent execution containers.
# When SANDBOX_MODE=true, the application runs in restricted mode.

module Sandbox
  class << self
    def enabled?
      Rails.configuration.respond_to?(:sandbox_mode) && Rails.configuration.sandbox_mode
    end

    def session_id
      Rails.configuration.sandbox_session_id if enabled?
    end

    def owner_id
      Rails.configuration.sandbox_owner_id if enabled?
    end

    def limits
      return {} unless enabled?

      {
        max_runs: Rails.configuration.sandbox_max_runs,
        timeout_seconds: Rails.configuration.sandbox_timeout_seconds,
        max_tokens: Rails.configuration.sandbox_max_tokens,
        idle_timeout: Rails.configuration.sandbox_idle_timeout
      }
    end

    def restricted_controllers
      # Controllers that are disabled in sandbox mode
      %w[
        admin
        billing
        subscriptions
        users
        registrations
        sessions
        passwords
      ]
    end

    def allowed_api_endpoints
      # Only these API endpoints are available in sandbox mode
      %w[
        /up
        /api/sandbox/status
        /api/sandbox/run
        /api/sandbox/runs
      ]
    end
  end
end

# Add sandbox restriction middleware
if Sandbox.enabled?
  Rails.application.config.sandbox_started_at = Time.current

  Rails.application.config.after_initialize do
    Rails.logger.info "[Sandbox] Starting in sandbox mode"
    Rails.logger.info "[Sandbox] Session ID: #{Sandbox.session_id}"
    Rails.logger.info "[Sandbox] Limits: #{Sandbox.limits.inspect}"

    # Set up auto-termination timer
    Thread.new do
      idle_timeout = Sandbox.limits[:idle_timeout] || 900
      last_activity = Time.current

      loop do
        sleep 60 # Check every minute

        current_activity = Thread.current[:sandbox_last_activity] || last_activity
        if Time.current - current_activity > idle_timeout
          Rails.logger.info "[Sandbox] Idle timeout reached after #{idle_timeout}s, shutting down"
          exit(0)
        end
      end
    end
  end
end
