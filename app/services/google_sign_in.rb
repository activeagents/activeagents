# frozen_string_literal: true

require "net/http"

# Used to learn who a person is on Google through the OpenID Connect
# authorization code flow, with PKCE, of this environment's OAuth client.
#
# The access token from the code exchange is used for one read of Google's
# userinfo endpoint and then dropped: it is never stored, logged or returned.
# The id_token in the same response is not used. It carries the claims
# userinfo does, and it arrives straight from Google's token endpoint over TLS
# in an exchange the client secret authenticates, so a signature check would
# add nothing.
#
# Configured by `google_oauth.client_id` / `google_oauth.client_secret` in the
# Rails credentials, falling back to GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET.
class GoogleSignIn
  class Error < StandardError; end

  # A Google account as sign-in sees it.
  #
  # @!attribute uid
  #   @return [String] Google's `sub` claim, the account id, which never changes
  # @!attribute name
  #   @return [String, nil] the profile's full name
  # @!attribute given_name
  #   @return [String, nil] the profile's first name
  # @!attribute family_name
  #   @return [String, nil] the profile's last name
  # @!attribute email
  #   @return [String, nil] the account's address, only when Google reports it verified
  Identity = Data.define(:uid, :name, :given_name, :family_name, :email)

  AUTHORIZE_URL = "https://accounts.google.com/o/oauth2/v2/auth"
  TOKEN_URL = "https://oauth2.googleapis.com/token"
  USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"
  SCOPE = "openid email profile"

  NETWORK_ERRORS = [
    Timeout::Error, SocketError, SystemCallError, IOError,
    OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
  ].freeze

  class << self
    def client_id
      Rails.application.credentials.dig(:google_oauth, :client_id).presence || ENV["GOOGLE_CLIENT_ID"].presence
    end

    def client_secret
      Rails.application.credentials.dig(:google_oauth, :client_secret).presence || ENV["GOOGLE_CLIENT_SECRET"].presence
    end

    def configured?
      client_id.present? && client_secret.present?
    end

    # Returns a fresh PKCE code verifier: 64 URL-safe characters, within the
    # 43 to 128 that RFC 7636 allows.
    def generate_code_verifier
      SecureRandom.urlsafe_base64(48)
    end

    # Returns the S256 challenge for `code_verifier`: its SHA-256, URL-safe
    # base64 without padding.
    def code_challenge(code_verifier)
      [ Digest::SHA256.digest(code_verifier) ].pack("m0").tr("+/", "-_").delete("=")
    end

    # Returns the Google page that asks the person to choose an account and
    # then sends them to `redirect_uri` with a code and `state`. The code is
    # bound to `code_verifier`, which the exchange has to present.
    def authorize_url(state:, redirect_uri:, code_verifier:)
      params = {
        client_id: client_id, redirect_uri: redirect_uri, response_type: "code", scope: SCOPE, state: state,
        code_challenge: code_challenge(code_verifier), code_challenge_method: "S256"
      }
      "#{AUTHORIZE_URL}?#{params.to_query}"
    end

    # Returns the Identity of the Google account that approved `code`. Raises
    # Error when Google refuses the code or the verifier, the userinfo read
    # fails, or Google cannot be reached.
    def identity_for(code:, redirect_uri:, code_verifier:)
      token = exchange_code(code, redirect_uri, code_verifier)
      info = get(token, USERINFO_URL)
      raise Error, "userinfo returned no sub" unless info.is_a?(Hash) && info["sub"].present?

      verified = [ true, "true" ].include?(info["email_verified"])
      Identity.new(
        uid: info["sub"].to_s, name: info["name"], given_name: info["given_name"], family_name: info["family_name"],
        email: verified ? info["email"].presence : nil
      )
    end

    private

    def exchange_code(code, redirect_uri, code_verifier)
      post = Net::HTTP::Post.new(URI(TOKEN_URL))
      post["Accept"] = "application/json"
      post.set_form_data(
        client_id: client_id, client_secret: client_secret, code: code, code_verifier: code_verifier,
        grant_type: "authorization_code", redirect_uri: redirect_uri
      )
      body = parse(perform(post))
      body = {} unless body.is_a?(Hash)
      # Google answers a refused code with 400 and an `error` field.
      body["access_token"].presence || raise(Error, "code exchange refused: #{body["error"] || "no access_token"}")
    end

    def get(token, url)
      request = Net::HTTP::Get.new(URI(url))
      request["Authorization"] = "Bearer #{token}"
      request["Accept"] = "application/json"
      response = perform(request)
      raise Error, "GET #{request.uri.path} returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      parse(response)
    end

    def perform(request)
      request["User-Agent"] = "ActiveAgents"
      uri = request.uri
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
    rescue *NETWORK_ERRORS => error
      raise Error, "#{request.method} #{uri.host}#{uri.path} failed: #{error.class}"
    end

    def parse(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise Error, "#{response.code} response was not JSON"
    end
  end
end
