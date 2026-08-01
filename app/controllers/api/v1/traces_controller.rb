# frozen_string_literal: true

module Api
  module V1
    # Telemetry ingestion endpoint for the hosted platform
    # (POST /v1/traces — the activeagent gem reporter's default endpoint).
    #
    # Authentication (Bearer Account#telemetry_api_key), payload handling and
    # async processing via ActiveAgent::ProcessTelemetryTracesJob are all
    # inherited from the gem's ingest controller; this subclass only layers
    # plan-based trace quotas on top.
    class TracesController < ActiveAgent::Dashboard::Api::TracesController
      # Replaces the gem's Bearer auth so dashboard-generated ApiKey tokens
      # (Settings -> API Keys) work in addition to the account's legacy
      # telemetry_api_key. Shared with the /v1/resources ingest.
      include IngestAuthentication

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
