# frozen_string_literal: true

module Api
  # Bearer authentication for the engine's ingest controllers as this app
  # serves them at /v1/traces and /v1/evaluations. Replaces the engine's
  # IngestAuthentication#authenticate_api_key!, which takes only an account's
  # telemetry_api_key, with Account.authenticate_api_token, which also takes a
  # key generated under Settings -> API Keys.
  module AccountTokenAuthentication
    extend ActiveSupport::Concern

    private

    def authenticate_api_key!
      token = extract_bearer_token

      if token.blank?
        render json: { error: "Missing Authorization header" }, status: :unauthorized
        return
      end

      @account = Account.authenticate_api_token(token)
      if @account.nil?
        render json: { error: "Invalid API key" }, status: :unauthorized
        return
      end

      record_ingest_request
    end
  end
end
