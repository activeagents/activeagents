# frozen_string_literal: true

require "net/http"
require "json"

# Decides whether a public form submission came from a person.
#
# Two layers, both cheap:
#
# * A honeypot: every protected form carries a text field named +website+
#   that people never see (it sits off screen, is skipped by the tab order and
#   hidden from assistive tech). Browsers leave it empty; form-filling bots
#   fill it in. A filled field is refused even when Turnstile is off.
# * Cloudflare Turnstile: when TURNSTILE_SITE_KEY and TURNSTILE_SECRET_KEY are
#   set, the form must carry a token the Turnstile widget issued, and that
#   token is verified with Cloudflare before the request goes on. Without the
#   two variables, Turnstile is off and only the honeypot applies, so a
#   deployment without a widget keeps working.
#
# Verification fails closed: a Cloudflare error or timeout refuses the
# submission rather than letting it through.
module HumanCheck
  HONEYPOT_FIELD = "website"
  TOKEN_FIELD = "cf-turnstile-response"
  VERIFY_URL = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")
  TIMEOUT = 5 # seconds, each for open and read

  Result = Struct.new(:ok, :reason) do
    def ok? = ok
  end

  module_function

  def enabled?
    site_key.present? && secret_key.present?
  end

  def site_key
    ENV["TURNSTILE_SITE_KEY"].presence
  end

  def secret_key
    ENV["TURNSTILE_SECRET_KEY"].presence
  end

  # Checks a request's parameters. +params+ responds to +[]+ (ActionController
  # parameters or a Hash); +remote_ip+ is the client's address, passed to
  # Cloudflare so the token is bound to the browser that solved it.
  def check(params, remote_ip:)
    return Result.new(false, :honeypot) if params[HONEYPOT_FIELD].present?
    return Result.new(true, nil) unless enabled?

    token = params[TOKEN_FIELD].to_s
    return Result.new(false, :missing_token) if token.blank?

    verify(token, remote_ip: remote_ip)
  end

  def verify(token, remote_ip:)
    response = Net::HTTP.start(VERIFY_URL.host, VERIFY_URL.port, use_ssl: true,
                               open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.post(VERIFY_URL.path, URI.encode_www_form(secret: secret_key, response: token, remoteip: remote_ip),
                "Content-Type" => "application/x-www-form-urlencoded")
    end
    return Result.new(false, :verify_http_error) unless response.is_a?(Net::HTTPSuccess)

    body = JSON.parse(response.body)
    if body["success"] == true
      Result.new(true, nil)
    else
      Result.new(false, Array(body["error-codes"]).first.presence || :rejected)
    end
  rescue JSON::ParserError
    Result.new(false, :verify_bad_response)
  rescue Timeout::Error, IOError, SystemCallError, OpenSSL::SSL::SSLError, Net::ProtocolError => error
    Rails.logger.warn("HumanCheck: Turnstile verification failed: #{error.class}: #{error.message}")
    Result.new(false, :verify_unreachable)
  end
end
