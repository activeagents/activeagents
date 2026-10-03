# frozen_string_literal: true

require "net/http"

# Used to learn who a person is on GitHub through the OAuth web flow of this
# environment's GitHub App (its user authorization, not an installation).
#
# The user access token from the code exchange is used for `GET /user` and
# `GET /user/emails` and then dropped: it is never stored, logged or returned.
# The App needs the read-only "Email addresses" account permission for the
# second read, and `/auth/github/callback` among its callback URLs.
#
# Configured by `github_app.client_id` / `github_app.client_secret` in the
# Rails credentials, falling back to GITHUB_APP_CLIENT_ID /
# GITHUB_APP_CLIENT_SECRET.
class GithubSignIn
  class Error < StandardError; end

  # A GitHub account as sign-in sees it.
  #
  # @!attribute uid
  #   @return [String] GitHub's numeric user id, which never changes
  # @!attribute login
  #   @return [String] the current username, which the person can change
  # @!attribute name
  #   @return [String, nil] the profile name
  # @!attribute email
  #   @return [String, nil] the primary address, only when GitHub reports it verified
  Identity = Data.define(:uid, :login, :name, :email)

  AUTHORIZE_URL = "https://github.com/login/oauth/authorize"
  TOKEN_URL = "https://github.com/login/oauth/access_token"
  API_URL = "https://api.github.com"

  NETWORK_ERRORS = [
    Timeout::Error, SocketError, SystemCallError, IOError,
    OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
  ].freeze

  class << self
    def client_id
      Rails.application.credentials.dig(:github_app, :client_id).presence || ENV["GITHUB_APP_CLIENT_ID"].presence
    end

    def client_secret
      Rails.application.credentials.dig(:github_app, :client_secret).presence || ENV["GITHUB_APP_CLIENT_SECRET"].presence
    end

    def configured?
      client_id.present? && client_secret.present?
    end

    # Returns the GitHub page that asks the person to authorize the App and
    # then sends them to `redirect_uri` with a code and `state`.
    def authorize_url(state:, redirect_uri:)
      "#{AUTHORIZE_URL}?#{{ client_id: client_id, redirect_uri: redirect_uri, state: state }.to_query}"
    end

    # Returns the Identity of the GitHub account that approved `code`. Raises
    # Error when GitHub refuses the code, either read fails, or GitHub cannot
    # be reached.
    def identity_for(code:, redirect_uri:)
      token = exchange_code(code, redirect_uri)
      account = get(token, "/user")
      emails = get(token, "/user/emails")
      raise Error, "GET /user returned no id" unless account.is_a?(Hash) && account["id"].present?
      raise Error, "GET /user/emails returned no list" unless emails.is_a?(Array)

      primary = emails.find { |address| address["primary"] && address["verified"] }
      Identity.new(uid: account["id"].to_s, login: account["login"], name: account["name"], email: primary&.dig("email"))
    end

    private

    def exchange_code(code, redirect_uri)
      post = Net::HTTP::Post.new(URI(TOKEN_URL))
      post["Accept"] = "application/json"
      post.set_form_data(client_id: client_id, client_secret: client_secret, code: code, redirect_uri: redirect_uri)
      body = parse(perform(post))
      body = {} unless body.is_a?(Hash)
      # GitHub answers a refused code with 200 and an `error` field.
      body["access_token"].presence || raise(Error, "code exchange refused: #{body["error"] || "no access_token"}")
    end

    def get(token, path)
      request = Net::HTTP::Get.new(URI("#{API_URL}#{path}"))
      request["Authorization"] = "Bearer #{token}"
      request["Accept"] = "application/vnd.github+json"
      request["X-GitHub-Api-Version"] = "2022-11-28"
      response = perform(request)
      raise Error, "GET #{path} returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

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
