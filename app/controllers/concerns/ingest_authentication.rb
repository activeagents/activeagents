# frozen_string_literal: true

# Bearer authentication for the machine ingest plane (/v1/*). Accepts a
# dashboard-generated ApiKey token (Settings -> API Keys) or the account's
# legacy telemetry_api_key — the same pair the telemetry ingest accepts —
# and sets @account. Session-authenticated dashboard read APIs live on a
# separate plane (Api::BaseController) and must stay there.
module IngestAuthentication
  extend ActiveSupport::Concern

  private

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

  def extract_bearer_token
    auth_header = request.headers["Authorization"]
    return nil if auth_header.blank?

    match = auth_header.match(/^Bearer\s+(.+)$/i)
    match[1] if match
  end
end
