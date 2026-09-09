# frozen_string_literal: true

module Api
  module V1
    # Telemetry ingestion endpoint for the hosted platform
    # (POST /v1/traces — the reporter's default endpoint).
    #
    # Authentication (Bearer Account#telemetry_api_key), payload handling and
    # async processing via ActionAgent::ProcessTelemetryTracesJob are all
    # inherited from the engine's ingest controller; this subclass only layers
    # plan-based trace quotas on top.
    class TracesController < ActionAgent::Api::TracesController
      before_action :enforce_trace_quota

      private

      # Extends the gem's Bearer auth to accept dashboard-generated ApiKey
      # tokens (Settings -> API Keys) in addition to the account's legacy
      # telemetry_api_key.
      def authenticate_api_key!
        token = extract_bearer_token

        if token.blank?
          render json: { error: "Missing Authorization header" }, status: :unauthorized
          return
        end

        if (api_key = ApiKey.authenticate(token))
          api_key.touch_last_used!
          @account = api_key.account
        else
          @account = Account.find_by(telemetry_api_key: token)
        end

        if @account.nil?
          render json: { error: "Invalid API key" }, status: :unauthorized
          return
        end

        @account.increment_telemetry_usage!
      end

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
