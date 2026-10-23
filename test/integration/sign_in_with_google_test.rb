require "test_helper"
require_relative "../support/pilot_helpers"

class SignInWithGoogleTest < ActionDispatch::IntegrationTest
  include PilotHelpers

  CLIENT_ID = "123456789-test.apps.googleusercontent.com"
  CLIENT_SECRET = "GOCSPX-test-client-secret"
  TOKEN_URL = "https://oauth2.googleapis.com/token"
  USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"
  CALLBACK_URL = "http://www.example.com/auth/google/callback"
  SUB = "10769150350006150715113082367"

  setup do
    create_pilot_plans
    @previous_env = ENV.to_h.slice("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "GITHUB_APP_CLIENT_ID", "GITHUB_APP_CLIENT_SECRET")
    ENV["GOOGLE_CLIENT_ID"] = CLIENT_ID
    ENV["GOOGLE_CLIENT_SECRET"] = CLIENT_SECRET
  end

  teardown do
    %w[ GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GITHUB_APP_CLIENT_ID GITHUB_APP_CLIENT_SECRET ].each { |key| ENV[key] = @previous_env[key] }
  end

  test "a new Google account signs up from its verified email and continues through onboarding" do
    state = start_google
    stub_google

    assert_difference [ "User.count", "Account.count", "AccountMembership.count", "UserIdentity.count" ], 1 do
      finish_google(state)
    end
    assert_redirected_to "/complete_profile"

    user = User.find_by!(email_address: "mona@example.com")
    assert user.email_verified?, "Google verified the address"
    assert_nil user.email_verification_token
    assert_not user.password_set?, "the random password is not one the person chose"
    assert_equal [ "Mona", "Lisa", "google" ], [ user.first_name, user.last_name, user.signup_source ]
    assert_equal [ SUB, nil, "mona@example.com" ], user.google_identity.slice(:uid, :login, :email).values
    assert_equal user, user.primary_account.owner
    assert_equal "owner", user.account_memberships.sole.role
    assert_exchanged_with_verifier_for @code_challenge

    follow_redirect!
    assert_response :success
    assert_select "input[name='user[first_name]'][value='Mona']"
    assert_select "input[name='user[password]'][required]", count: 0
    assert_select "p", /You sign in with Google\./

    patch "/complete_profile", params: { user: { first_name: "Mona", last_name: "Lisa" }, plan_slug: "free" }
    assert_redirected_to "/dashboard"
    assert user.reload.profile_completed?
    assert_not user.password_set?
    get "/dashboard/api/agents", as: :json
    assert_response :success
  end

  test "a profile without given and family names is split from the full name" do
    state = start_google
    stub_google(given_name: nil, family_name: nil, name: "Mona Lisa Gherardini")

    finish_google(state)
    assert_redirected_to "/complete_profile"
    user = User.find_by!(email_address: "mona@example.com")
    assert_equal [ "Mona", "Lisa Gherardini" ], [ user.first_name, user.last_name ]
  end

  test "each round trip gets its own verifier, and the exchange presents the one for the challenge it asked for" do
    start_google
    first_challenge = @code_challenge
    state = start_google
    assert_not_equal first_challenge, @code_challenge
    stub_google

    finish_google(state)
    assert_redirected_to "/complete_profile"
    assert_exchanged_with_verifier_for @code_challenge
  end

  test "a returning Google account signs in as its user by Google id and returns to the page that asked" do
    user = create_user(email: "returning@example.com")
    create_account(owner: user)
    user.identities.create!(provider: "google", uid: SUB, email: "old@example.com")

    get "/settings"
    assert_redirected_to "/session/new"
    state = start_google
    # The account's Google address now matches no user here; the id still does.
    stub_google(email: "mona@example.com")

    assert_no_difference [ "User.count", "Account.count", "UserIdentity.count" ] do
      finish_google(state)
    end
    assert_redirected_to "http://www.example.com/settings"
    assert_equal "mona@example.com", user.google_identity.reload.email

    follow_redirect!
    assert_response :success
    assert_select "strong", "mona@example.com"
  end

  test "a Google sign-in whose email already has an account is sent to the password sign-in instead of linking" do
    existing = create_user(email: "mona@example.com")
    create_account(owner: existing)
    state = start_google
    stub_google(email: "Mona@Example.com")

    assert_no_difference [ "User.count", "UserIdentity.count", "Session.count" ] do
      finish_google(state)
    end
    assert_redirected_to "/session/new"
    assert_match "Sign in with your password, or reset it with Forgot your password?, then connect Google from Settings", flash[:notice]

    sign_in_as(existing)
    assert_redirected_to "http://www.example.com/settings"
    assert_nil existing.reload.google_identity
  end

  test "an unverified account with the Google email is neither linked nor verified" do
    # Anyone can register an address they do not own; it stays unverified.
    squatter = User.create!(email_address: "mona@example.com", password: "squatter-password")
    state = start_google
    stub_google

    assert_no_difference [ "User.count", "UserIdentity.count", "Session.count" ] do
      finish_google(state)
    end
    assert_redirected_to "/session/new"
    assert_not squatter.reload.email_verified?
    assert_nil squatter.google_identity
  end

  test "a Google account whose email is not verified cannot sign up" do
    state = start_google
    stub_google(email_verified: false)

    assert_no_difference [ "User.count", "UserIdentity.count", "Session.count" ] do
      finish_google(state)
    end
    assert_redirected_to "/session/new"
    assert_match "email address isn't verified", flash[:alert]
  end

  test "a callback whose state does not match is refused before Google is called and spends the real state" do
    state = start_google
    stub_google

    assert_no_difference [ "User.count", "Session.count" ] do
      get "/auth/google/callback", params: { code: "good-code", state: "forged-state" }
      assert_redirected_to "/session/new"
      finish_google(state)
      assert_redirected_to "/session/new"
    end
    assert_match "no longer valid", flash[:alert]
    assert_not_requested :post, TOKEN_URL
  end

  test "a callback with no sign-in started in this browser is refused" do
    stub_google

    get "/auth/google/callback", params: { code: "good-code", state: "any-state" }
    assert_redirected_to "/session/new"
    assert_not_requested :post, TOKEN_URL
  end

  test "a state is good for one callback and expires" do
    user = create_user(email: "returning@example.com")
    create_account(owner: user)
    user.identities.create!(provider: "google", uid: SUB, email: "returning@example.com")
    stub_google

    state = start_google
    finish_google(state)
    assert_redirected_to "http://www.example.com/workspace"
    delete "/session"
    finish_google(state)
    assert_redirected_to "/session/new"

    state = start_google
    travel GoogleAuthorization::STATE_TTL + 1.second do
      finish_google(state)
    end
    assert_redirected_to "/session/new"
    assert_requested :post, TOKEN_URL, times: 1
  end

  test "a cancelled authorization signs nobody in" do
    state = start_google

    get "/auth/google/callback", params: { error: "access_denied", state: state }
    assert_redirected_to "/session/new"
    assert_equal "Google sign-in was cancelled.", flash[:alert]
    assert_not_requested :post, TOKEN_URL
  end

  test "a cancelled connect returns to Settings" do
    user = create_user(email: "connect@example.com")
    create_account(owner: user)
    sign_in_as(user)
    state = start_google("/settings/google")

    get "/auth/google/callback", params: { error: "access_denied", state: state }
    assert_redirected_to "/settings"
    assert_equal "Connecting Google was cancelled.", flash[:alert]
    assert_nil user.reload.google_identity
    assert_not_requested :post, TOKEN_URL
  end

  test "a Google email the account rules reject creates nothing" do
    state = start_google
    stub_google(email: "#{"m" * 250}@example.com")

    assert_no_difference [ "User.count", "Account.count", "UserIdentity.count", "Session.count" ] do
      finish_google(state)
    end
    assert_redirected_to "/session/new"
    assert_match "We couldn't create an account from Google: Email address is too long", flash[:alert]
  end

  test "a code Google refuses, or Google being unreachable, signs nobody in" do
    stub_request(:post, TOKEN_URL).to_return(status: 400, body: { error: "invalid_grant" }.to_json).then.to_timeout

    2.times do
      state = start_google
      assert_no_difference [ "User.count", "Session.count" ] do
        finish_google(state)
      end
      assert_redirected_to "/session/new"
      assert_match "Google didn't confirm your account", flash[:alert]
    end
  end

  test "a signed-in user connects Google from Settings and can then sign in with it" do
    user = create_user(email: "connect@example.com")
    create_account(owner: user)
    sign_in_as(user)
    get "/settings"
    assert_select "button", "Connect Google"

    state = start_google("/settings/google")
    stub_google(email: "personal@example.com")
    assert_difference "UserIdentity.count", 1 do
      finish_google(state)
    end
    assert_redirected_to "/settings"
    assert_equal "Connected Google as personal@example.com.", flash[:notice]
    assert_equal [ SUB, "personal@example.com" ], user.google_identity.slice(:uid, :email).values
    assert_equal "connect@example.com", user.reload.email_address

    delete "/session"
    finish_google(start_google)
    assert_redirected_to "http://www.example.com/workspace"
  end

  test "connecting refuses a Google account another user has connected" do
    other = create_user(email: "other@example.com")
    other.identities.create!(provider: "google", uid: SUB, email: "other@example.com")
    user = create_user(email: "connect@example.com")
    create_account(owner: user)
    sign_in_as(user)

    state = start_google("/settings/google")
    stub_google
    assert_no_difference "UserIdentity.count" do
      finish_google(state)
    end
    assert_redirected_to "/settings"
    assert_match "connected to another ActiveAgents account", flash[:alert]
    assert_nil user.reload.google_identity
    assert_equal other, UserIdentity.find_by!(provider: "google", uid: SUB).user
  end

  test "connecting the Google account already connected refreshes its email" do
    user = create_user(email: "connect@example.com")
    create_account(owner: user)
    user.identities.create!(provider: "google", uid: SUB, email: "old@example.com")
    sign_in_as(user)

    state = start_google("/settings/google")
    stub_google(email: "new@example.com")
    assert_no_difference "UserIdentity.count" do
      finish_google(state)
    end
    assert_redirected_to "/settings"
    assert_equal "Google is already connected.", flash[:notice]
    assert_equal "new@example.com", user.google_identity.reload.email
  end

  test "connecting a second Google account is refused until the first is disconnected" do
    user = create_user(email: "connect@example.com")
    create_account(owner: user)
    user.identities.create!(provider: "google", uid: "1111", email: "first@example.com")
    sign_in_as(user)

    state = start_google("/settings/google")
    stub_google(email: "second@example.com")
    assert_no_difference "UserIdentity.count" do
      finish_google(state)
    end
    assert_redirected_to "/settings"
    assert_equal "Disconnect first@example.com before connecting another Google account.", flash[:alert]
    assert_equal "1111", user.google_identity.reload.uid
  end

  test "a connect that loses a race for the Google account to another user is refused" do
    other = create_user(email: "other@example.com")
    other.identities.create!(provider: "google", uid: SUB, email: "other@example.com")
    user = create_user(email: "connect@example.com")
    create_account(owner: user)
    sign_in_as(user)
    state = start_google("/settings/google")
    stub_google

    # The other user's connect lands after the controller looked the uid up.
    with_method(UserIdentity, :find_by, ->(*) { nil }) do
      assert_no_difference "UserIdentity.count" do
        finish_google(state)
      end
    end
    assert_redirected_to "/settings"
    assert_equal "That Google account is connected to another ActiveAgents account.", flash[:alert]
    assert_nil user.reload.google_identity
  end

  test "a connect completes only for the user and session that started it" do
    first = create_user(email: "first@example.com")
    create_account(owner: first)
    second = create_user(email: "second@example.com")
    create_account(owner: second)
    stub_google

    sign_in_as(first)
    state = start_google("/settings/google")
    delete "/session"
    sign_in_as(second)

    assert_no_difference "UserIdentity.count" do
      finish_google(state)
    end
    assert_redirected_to "/session/new"
    assert_not_requested :post, TOKEN_URL
  end

  test "disconnecting is refused while Google is the only way to sign in" do
    user = User.new(email_address: "mona@example.com", email_verified: true)
    user.assign_random_password
    user.save_with_workspace
    user.identities.create!(provider: "google", uid: SUB, email: "mona@example.com")
    stub_google
    finish_google(start_google)

    get "/settings"
    assert_select "p", "You haven't set a password, so Google is the only way to sign in to this account."
    assert_select "button", text: "Disconnect Google", count: 0
    delete "/settings/google"
    assert_redirected_to "/settings"
    assert_match "Set a password before disconnecting Google", flash[:alert]
    assert user.reload.google_identity

    user.update!(password: "chosen-password", password_confirmation: "chosen-password")
    delete "/settings/google"
    assert_redirected_to "/settings"
    assert_nil user.reload.google_identity
  end

  test "with GitHub and Google both connected, either can be disconnected without a password, but not the last one" do
    user = User.new(email_address: "mona@example.com", email_verified: true)
    user.assign_random_password
    user.save_with_workspace
    user.identities.create!(provider: "github", uid: "4242", login: "octocat")
    user.identities.create!(provider: "google", uid: SUB, email: "mona@example.com")
    stub_google
    finish_google(start_google)

    get "/settings"
    assert_select "p", "You haven't set a password, so GitHub and Google are the only ways to sign in to this account."
    assert_select "button", "Disconnect GitHub"
    assert_select "button", "Disconnect Google"

    assert_difference "UserIdentity.count", -1 do
      delete "/settings/github"
    end
    assert_redirected_to "/settings"
    get "/settings"
    assert_select "p", "You haven't set a password, so Google is the only way to sign in to this account."
    assert_select "button", text: "Disconnect Google", count: 0
    assert_no_difference "UserIdentity.count" do
      delete "/settings/google"
    end
    assert_match "Set a password before disconnecting Google", flash[:alert]
  end

  test "a user with a password disconnects Google" do
    user = create_user(email: "connected@example.com")
    create_account(owner: user)
    user.identities.create!(provider: "google", uid: SUB, email: "connected@example.com")
    sign_in_as(user)

    get "/settings"
    assert_select "strong", "connected@example.com"
    assert_select "button", "Disconnect Google"
    assert_difference "UserIdentity.count", -1 do
      delete "/settings/google"
    end
    assert_redirected_to "/settings"
    assert_equal "Disconnected Google.", flash[:notice]
  end

  test "Google buttons appear only when the OAuth client is configured" do
    get "/session/new"
    assert_select "form[action='/auth/google'] button", "Sign in with Google"
    get "/registration/new"
    assert_select "form[action='/auth/google'] button", "Sign up with Google"

    ENV.delete("GOOGLE_CLIENT_SECRET")
    get "/session/new"
    assert_select "form[action='/auth/google']", count: 0
    get "/registration/new"
    assert_select "form[action='/auth/google']", count: 0
    post "/auth/google"
    assert_response :not_found
  end

  test "the sign-in page shows one email divider however many providers are on" do
    ENV["GITHUB_APP_CLIENT_ID"] = "Iv23liTestClientId"
    ENV["GITHUB_APP_CLIENT_SECRET"] = "test-client-secret"

    get "/session/new"
    assert_select "form[action='/auth/github'] button", "Sign in with GitHub"
    assert_select "form[action='/auth/google'] button", "Sign in with Google"
    assert_select "span", text: "or use your email", count: 1

    ENV.delete("GITHUB_APP_CLIENT_ID")
    ENV.delete("GOOGLE_CLIENT_ID")
    get "/session/new"
    assert_select "span", text: "or use your email", count: 0
  end

  private

  # Starts a Google round trip and returns the state Google would send back.
  # Keeps the PKCE challenge it asked for in @code_challenge.
  def start_google(path = "/auth/google")
    post path
    assert_response :redirect
    location = URI(response.location)
    assert_equal "https://accounts.google.com/o/oauth2/v2/auth", "#{location.scheme}://#{location.host}#{location.path}"
    query = Rack::Utils.parse_query(location.query)
    assert_equal [ CLIENT_ID, CALLBACK_URL, "code", "openid email profile", "S256" ],
      query.values_at("client_id", "redirect_uri", "response_type", "scope", "code_challenge_method")
    @code_challenge = query.fetch("code_challenge")
    query.fetch("state")
  end

  def finish_google(state, code: "good-code")
    get "/auth/google/callback", params: { code: code, state: state }
  end

  def assert_exchanged_with_verifier_for(challenge)
    assert_requested(:post, TOKEN_URL) do |request|
      body = Rack::Utils.parse_query(request.body)
      body.slice("client_id", "client_secret", "code", "grant_type", "redirect_uri") ==
        { "client_id" => CLIENT_ID, "client_secret" => CLIENT_SECRET, "code" => "good-code", "grant_type" => "authorization_code", "redirect_uri" => CALLBACK_URL } &&
        GoogleSignIn.code_challenge(body["code_verifier"].to_s) == challenge
    end
  end

  def stub_google(sub: SUB, name: "Mona Lisa", given_name: "Mona", family_name: "Lisa", email: "mona@example.com", email_verified: true)
    token = "ya29.#{SecureRandom.hex(8)}"
    stub_request(:post, TOKEN_URL).to_return(json(access_token: token, token_type: "Bearer", expires_in: 3599, scope: "openid email profile", id_token: "unused"))
    stub_request(:get, USERINFO_URL).with(headers: { "Authorization" => "Bearer #{token}" })
      .to_return(json({ sub: sub, name: name, given_name: given_name, family_name: family_name, email: email, email_verified: email_verified,
        picture: "https://lh3.googleusercontent.com/a/photo" }.compact))
  end

  def json(body)
    { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end
end
