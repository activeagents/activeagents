# frozen_string_literal: true

module Api
  module V1
    # Ingestion endpoint for ActiveAgent telemetry traces.
    #
    # Receives traces from ActiveAgent::Telemetry::Reporter and stores them
    # for analysis and visualization in the dashboard.
    #
    # Authentication is via Bearer token in the Authorization header.
    # The token must match an Account's telemetry_api_key.
    #
    # @example Request
    #   POST /api/v1/traces
    #   Authorization: Bearer <api_key>
    #   Content-Type: application/json
    #
    #   {
    #     "traces": [...],
    #     "sdk": { "name": "activeagent", "version": "0.5.0" }
    #   }
    #
    class TracesController < Api::BaseController
      # Skip session-based authentication - we use API key auth instead
      skip_before_action :require_authentication, raise: false
      skip_before_action :allow_browser, raise: false
      before_action :authenticate_api_key!

      # POST /api/v1/traces
      #
      # Ingests traces from ActiveAgent telemetry clients.
      #
      # @param traces [Array<Hash>] Array of trace payloads
      # @param sdk [Hash] SDK metadata (name, version, language, runtime_version)
      #
      # @return [202 Accepted] on success
      # @return [401 Unauthorized] if API key is invalid
      # @return [422 Unprocessable Entity] if traces are malformed
      def create
        traces = params[:traces] || []
        sdk_info = params[:sdk] || {}

        return head :accepted if traces.empty?

        # Process traces in background to avoid blocking the client
        ProcessTelemetryTracesJob.perform_later(
          account_id: @account.id,
          traces: traces.as_json,
          sdk_info: sdk_info.as_json,
          received_at: Time.current.iso8601(6)
        )

        head :accepted
      rescue ActionController::ParameterMissing => e
        render json: { error: e.message }, status: :bad_request
      end

      private

      # Authenticates the request using Bearer token from Authorization header.
      #
      # The token must match an Account's telemetry_api_key field.
      #
      # @raise [401 Unauthorized] if token is missing or invalid
      def authenticate_api_key!
        token = extract_bearer_token

        if token.blank?
          render json: { error: "Missing Authorization header" }, status: :unauthorized
          return
        end

        @account = Account.find_by(telemetry_api_key: token)

        if @account.nil?
          render json: { error: "Invalid API key" }, status: :unauthorized
          return
        end

        # Track usage for rate limiting (optional)
        @account.increment_telemetry_usage!
      end

      # Extracts Bearer token from Authorization header.
      #
      # @return [String, nil] The token or nil
      def extract_bearer_token
        auth_header = request.headers["Authorization"]
        return nil if auth_header.blank?

        match = auth_header.match(/^Bearer\s+(.+)$/i)
        match[1] if match
      end
    end
  end
end
