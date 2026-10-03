require "test_helper"

class GithubSignInTest < ActiveSupport::TestCase
  TOKEN_URL = "https://github.com/login/oauth/access_token"

  setup do
    @previous_env = ENV.to_h.slice("GITHUB_APP_CLIENT_ID", "GITHUB_APP_CLIENT_SECRET")
    ENV["GITHUB_APP_CLIENT_ID"] = "Iv23liTestClientId"
    ENV["GITHUB_APP_CLIENT_SECRET"] = "test-client-secret"
  end

  teardown do
    %w[ GITHUB_APP_CLIENT_ID GITHUB_APP_CLIENT_SECRET ].each { |key| ENV[key] = @previous_env[key] }
  end

  test "is configured only with both a client id and a client secret" do
    assert GithubSignIn.configured?
    ENV.delete("GITHUB_APP_CLIENT_ID")
    assert_not GithubSignIn.configured?
  end

  test "authorize_url asks GitHub to send the person back with the state" do
    url = URI(GithubSignIn.authorize_url(state: "abc", redirect_uri: "https://app.example.com/auth/github/callback"))
    query = Rack::Utils.parse_query(url.query)

    assert_equal "https://github.com/login/oauth/authorize", "#{url.scheme}://#{url.host}#{url.path}"
    assert_equal({ "client_id" => "Iv23liTestClientId", "redirect_uri" => "https://app.example.com/auth/github/callback", "state" => "abc" }, query)
  end

  test "identity_for reads the account and only its verified primary email" do
    stub_exchange
    stub_api("/user", { id: 99, login: "octocat", name: nil })
    stub_api("/user/emails", [
      { email: "secondary@example.com", primary: false, verified: true },
      { email: "primary@example.com", primary: true, verified: true }
    ])

    identity = GithubSignIn.identity_for(code: "code", redirect_uri: "https://app.example.com/auth/github/callback")
    assert_equal GithubSignIn::Identity.new(uid: "99", login: "octocat", name: nil, email: "primary@example.com"), identity
  end

  test "identity_for raises when the App cannot read email addresses" do
    stub_exchange
    stub_api("/user", { id: 99, login: "octocat" })
    stub_request(:get, "https://api.github.com/user/emails").to_return(status: 403, body: { message: "Resource not accessible by integration" }.to_json)

    error = assert_raises(GithubSignIn::Error) { GithubSignIn.identity_for(code: "code", redirect_uri: "https://app.example.com/cb") }
    assert_equal "GET /user/emails returned 403", error.message
  end

  test "identity_for raises without the token when GitHub refuses the code or cannot be reached" do
    stub_request(:post, TOKEN_URL).to_return(status: 200, body: { error: "bad_verification_code" }.to_json)
      .then.to_timeout

    error = assert_raises(GithubSignIn::Error) { GithubSignIn.identity_for(code: "code", redirect_uri: "https://app.example.com/cb") }
    assert_equal "code exchange refused: bad_verification_code", error.message
    error = assert_raises(GithubSignIn::Error) { GithubSignIn.identity_for(code: "code", redirect_uri: "https://app.example.com/cb") }
    assert_match "POST github.com/login/oauth/access_token failed", error.message
    assert_not_requested :get, "https://api.github.com/user"
  end

  private

  def stub_exchange
    stub_request(:post, TOKEN_URL).with(headers: { "Accept" => "application/json" })
      .to_return(status: 200, body: { access_token: "ghu_secret", token_type: "bearer" }.to_json)
  end

  def stub_api(path, body)
    stub_request(:get, "https://api.github.com#{path}")
      .with(headers: { "Authorization" => "Bearer ghu_secret", "X-GitHub-Api-Version" => "2022-11-28" })
      .to_return(status: 200, body: body.to_json)
  end
end
