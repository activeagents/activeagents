require "test_helper"

class GoogleSignInTest < ActiveSupport::TestCase
  TOKEN_URL = "https://oauth2.googleapis.com/token"
  USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"
  CALLBACK_URL = "https://app.example.com/auth/google/callback"

  setup do
    @previous_env = ENV.to_h.slice("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET")
    ENV["GOOGLE_CLIENT_ID"] = "123456789-test.apps.googleusercontent.com"
    ENV["GOOGLE_CLIENT_SECRET"] = "GOCSPX-test-client-secret"
  end

  teardown do
    %w[ GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET ].each { |key| ENV[key] = @previous_env[key] }
  end

  test "is configured only with both a client id and a client secret" do
    assert GoogleSignIn.configured?
    ENV.delete("GOOGLE_CLIENT_ID")
    assert_not GoogleSignIn.configured?
  end

  test "client id and secret from the environment are stripped of stray whitespace" do
    ENV["GOOGLE_CLIENT_ID"] = "123456789-test.apps.googleusercontent.com\n"
    ENV["GOOGLE_CLIENT_SECRET"] = " GOCSPX-test-client-secret\n"

    assert_equal "123456789-test.apps.googleusercontent.com", GoogleSignIn.client_id
    assert_equal "GOCSPX-test-client-secret", GoogleSignIn.client_secret
    assert GoogleSignIn.configured?
  end

  test "authorize_url asks Google for a code bound to the verifier's challenge and the state" do
    url = URI(GoogleSignIn.authorize_url(state: "abc", redirect_uri: CALLBACK_URL, code_verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
    query = Rack::Utils.parse_query(url.query)

    assert_equal "https://accounts.google.com/o/oauth2/v2/auth", "#{url.scheme}://#{url.host}#{url.path}"
    assert_equal({
      "client_id" => "123456789-test.apps.googleusercontent.com", "redirect_uri" => CALLBACK_URL, "response_type" => "code",
      "scope" => "openid email profile", "state" => "abc",
      "code_challenge" => "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "code_challenge_method" => "S256"
    }, query)
  end

  test "code_challenge is the verifier's SHA-256 in unpadded URL-safe base64, as RFC 7636 shows" do
    assert_equal "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", GoogleSignIn.code_challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
  end

  test "generate_code_verifier makes a fresh verifier of allowed characters and length" do
    verifiers = Array.new(3) { GoogleSignIn.generate_code_verifier }

    assert_equal 3, verifiers.uniq.size
    verifiers.each do |verifier|
      assert_match(/\A[A-Za-z0-9\-._~]{43,128}\z/, verifier)
    end
  end

  test "identity_for exchanges the code with the verifier, reads userinfo and keeps a verified email" do
    stub_exchange
    stub_userinfo(sub: 99, name: "Mona Lisa", given_name: "Mona", family_name: "Lisa", email: "mona@example.com", email_verified: true)

    identity = GoogleSignIn.identity_for(code: "code", redirect_uri: CALLBACK_URL, code_verifier: "verifier")

    assert_equal GoogleSignIn::Identity.new(uid: "99", name: "Mona Lisa", given_name: "Mona", family_name: "Lisa", email: "mona@example.com"), identity
    assert_requested :post, TOKEN_URL, body: {
      "client_id" => "123456789-test.apps.googleusercontent.com", "client_secret" => "GOCSPX-test-client-secret",
      "code" => "code", "code_verifier" => "verifier", "grant_type" => "authorization_code", "redirect_uri" => CALLBACK_URL
    }
  end

  test "identity_for drops an email Google has not verified" do
    stub_exchange
    stub_userinfo(sub: 99, name: "Mona Lisa", email: "mona@example.com", email_verified: false)

    identity = GoogleSignIn.identity_for(code: "code", redirect_uri: CALLBACK_URL, code_verifier: "verifier")

    assert_nil identity.email
    assert_equal [ "99", "Mona Lisa", nil, nil ], [ identity.uid, identity.name, identity.given_name, identity.family_name ]
  end

  test "identity_for raises when userinfo refuses the token or names no account" do
    stub_exchange
    stub_request(:get, USERINFO_URL).to_return(status: 401, body: { error: "invalid_token" }.to_json)
    error = assert_raises(GoogleSignIn::Error) { GoogleSignIn.identity_for(code: "code", redirect_uri: CALLBACK_URL, code_verifier: "verifier") }
    assert_equal "GET /v1/userinfo returned 401", error.message

    stub_userinfo(email: "mona@example.com", email_verified: true)
    error = assert_raises(GoogleSignIn::Error) { GoogleSignIn.identity_for(code: "code", redirect_uri: CALLBACK_URL, code_verifier: "verifier") }
    assert_equal "userinfo returned no sub", error.message
  end

  test "identity_for raises without the token when Google refuses the code or cannot be reached" do
    stub_request(:post, TOKEN_URL).to_return(status: 400, body: { error: "invalid_grant", error_description: "Bad Request" }.to_json)
      .then.to_timeout

    error = assert_raises(GoogleSignIn::Error) { GoogleSignIn.identity_for(code: "code", redirect_uri: CALLBACK_URL, code_verifier: "verifier") }
    assert_equal "code exchange refused: invalid_grant", error.message
    error = assert_raises(GoogleSignIn::Error) { GoogleSignIn.identity_for(code: "code", redirect_uri: CALLBACK_URL, code_verifier: "verifier") }
    assert_match "POST oauth2.googleapis.com/token failed", error.message
    assert_not_requested :get, USERINFO_URL
  end

  private

  def stub_exchange
    stub_request(:post, TOKEN_URL).with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: { access_token: "ya29.secret", token_type: "Bearer", expires_in: 3599, id_token: "unused" }.to_json)
  end

  def stub_userinfo(**claims)
    stub_request(:get, USERINFO_URL).with(headers: { "Authorization" => "Bearer ya29.secret" })
      .to_return(status: 200, body: claims.to_json)
  end
end
