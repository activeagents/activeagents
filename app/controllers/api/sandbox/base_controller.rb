# frozen_string_literal: true

module Api
  module Sandbox
    class BaseController < ActionController::API
      before_action :require_sandbox_mode!
      before_action :track_activity

      private

      def require_sandbox_mode!
        unless ::Sandbox.enabled?
          render json: { error: "This endpoint is only available in sandbox mode" }, status: :forbidden
        end
      end

      def track_activity
        @last_activity_at = Time.current
        # Update activity tracking for idle timeout
        Thread.current[:sandbox_last_activity] = @last_activity_at
      end

      def sandbox_session_id
        ::Sandbox.session_id
      end

      def sandbox_limits
        ::Sandbox.limits
      end
    end
  end
end
