# frozen_string_literal: true

module Api
  module V1
    # Telemetry ingestion endpoint for the hosted platform
    # (POST /v1/traces — the activeagent reporter's default endpoint).
    #
    # Payload handling and async processing via
    # ActionAgent::ProcessTelemetryTracesJob are inherited from the engine's
    # ingest controller. This subclass takes the account keys
    # Api::AccountTokenAuthentication accepts, and enforces the plan's trace
    # quota.
    class TracesController < ActionAgent::Api::TracesController
      include Api::AccountTokenAuthentication

      before_action :enforce_trace_quota

      private

      def enforce_trace_quota
        return if @account.nil? || @account.can_ingest_traces?

        render json: {
          error: "Trace quota exceeded for current plan",
          limit: @account.effective_trace_limit
        }, status: :too_many_requests
      end
    end
  end
end
