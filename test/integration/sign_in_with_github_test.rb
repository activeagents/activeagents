require "test_helper"
require_relative "../support/pilot_helpers"

class SignInWithGithubTest < ActionDispatch::IntegrationTest
  include PilotHelpers

  CLIENT_ID = "Iv23liTestClientId"
  CLIENT_SECRET = "test-client-secret"
  TOKEN_URL = "https://github.com/login/oauth/access_token"
  CALLBACK_URL = "http://www.example.com/auth/github/callback"
  VERIFIED_PRIMARY = [ { "email" => "mona@example.com", "primary" => true, "verified" => true } ].freeze

  setup do
    create_pilot_plans
    @previous_env = ENV.to_h.slice("GITHUB_APP_CLIENT_ID", "GITHUB_APP_CLIENT_SECRET")
    ENV["GITHUB_APP_CLIENT_ID"] = CLIENT_ID
    ENV["GITHUB_APP_CLIENT_SECRET"] = CLIENT_SECRET
  end

  teardown do
    %w[ GITHUB_APP_CLIENT_ID GITHUB_APP_CLIENT_SECRET ].each { |key| ENV[key] = @previous_env[key] }
  end

  test "a new GitHub account signs up from its verified primary email and continues through onboarding" do
    state = start_github
    stub_github

    assert_difference [ "User.count", "Account.count", "AccountMembership.count", "UserIdentity.count" ], 1 do
      finish_github(state)
    end
    assert_redirected_to "/complete_profile"

    user = User.find_by!(email_address: "mona@example.com")
    assert user.email_verified?, "GitHub verified the address"
    assert_nil user.email_verification_token
    assert_not user.password_set?, "the random password is not one the person chose"
    assert_equal [ "Mona", "Octocat", "github" ], [ user.first_name, user.last_name, user.signup_source ]
    assert_equal [ "4242", "octocat", "mona@example.com" ], user.github_identity.slice(:uid, :login, :email).values
    assert_equal user, user.primary_account.owner
    assert_equal "owner", user.account_memberships.sole.role
    assert_requested :post, TOKEN_URL,
      body: { "client_id" => CLIENT_ID, "client_secret" => CLIENT_SECRET, "code" => "good-code", "redirect_uri" => CALLBACK_URL }

    follow_redirect!
    assert_response :success
    assert_select "input[name='user[first_name]'][value='Mona']"
    assert_select "input[name='user[password]'][required]", count: 0

    patch "/complete_profile", params: { user: { first_name: "Mona", last_name: "Octocat" }, plan_slug: "free" }
    assert_redirected_to "/dashboard"
    assert user.reload.profile_completed?
    assert_not user.password_set?
    get "/dashboard/api/agents", as: :json
    assert_response :success
  end

  test "a returning GitHub account signs in as its user by GitHub id and returns to the page that asked" do
    user = create_user(email: "returning@example.com")
    create_account(owner: user)
    user.identities.create!(provider: "github", uid: "4242", login: "old-login", email: "returning@example.com")

    get "/settings"
    assert_redirected_to "/session/new"
    state = start_github
    # The account's GitHub address now matches no user here; the id still does.
    stub_github(login: "new-login", emails: [ { "email" => "mona@example.com", "primary" => true, "verified" => true } ])

    assert_no_difference [ "User.count", "Account.count", "UserIdentity.count" ] do
      finish_github(state)
    end
    assert_redirected_to "http://www.example.com/settings"
    assert_equal "new-login", user.github_identity.reload.login

    follow_redirect!
    assert_response :success
    assert_select "strong", "@new-login"
  end

  test "a GitHub sign-in whose email already has an account is sent to the password sign-in instead of linking" do
    existing = create_user(email: "mona@example.com")
    create_account(owner: existing)
    state = start_github
    stub_github(emails: [ { "email" => "Mona@Example.com", "primary" => true, "verified" => true } ])

    assert_no_difference [ "User.count", "UserIdentity.count", "Session.count" ] do
      finish_github(state)
    end
    assert_redirected_to "/session/new"
    assert_match "Sign in with your password, then connect GitHub from Settings", flash[:notice]

    sign_in_as(existing)
    assert_redirected_to "http://www.example.com/settings"
    assert_nil existing.reload.github_identity
  end

  test "an unverified account with the GitHub email is neither linked nor verified" do
    # Anyone can register an address they do not own; it stays unverified.
    squatter = User.create!(email_address: "mona@example.com", password: "squatter-password")
    state = start_github
    stub_github

    assert_no_difference [ "User.count", "UserIdentity.count", "Session.count" ] do
      finish_github(state)
    end
    assert_redirected_to "/session/new"
    assert_not squatter.reload.email_verified?
    assert_nil squatter.github_identity
  end

  test "a GitHub account without a verified primary email cannot sign up" do
    state = start_github
    stub_github(emails: [
      { "email" => "mona@example.com", "primary" => true, "verified" => false },
      { "email" => "mona@work.example.com", "primary" => false, "verified" => true }
    ])

    assert_no_difference [ "User.count", "UserIdentity.count", "Session.count" ] do
      finish_github(state)
    end
    assert_redirected_to "/session/new"
    assert_match "no verified primary email address", flash[:alert]
  end

  test "a callback whose state does not match is refused before GitHub is called and spends the real state" do
    state = start_github
    stub_github

    assert_no_difference [ "User.count", "Session.count" ] do
      get "/auth/github/callback", params: { code: "good-code", state: "forged-state" }
      assert_redirected_to "/session/new"
      finish_github(state)
      assert_redirected_to "/session/new"
    end
    assert_match "no longer valid", flash[:alert]
    assert_not_requested :post, TOKEN_URL
  end

  test "a callback with no sign-in started in this browser is refused" do
    stub_github

    get "/auth/github/callback", params: { code: "good-code", state: "any-state" }
    assert_redirected_to "/session/new"
    assert_not_requested :post, TOKEN_URL
  end

  test "a state is good for one callback and expires" do
    user = create_user(email: "returning@example.com")
    create_account(owner: user)
    user.identities.create!(provider: "github", uid: "4242", login: "octocat")
    stub_github

    state = start_github
    finish_github(state)
    assert_redirected_to "http://www.example.com/workspace"
    delete "/session"
    finish_github(state)
    assert_redirected_to "/session/new"

    state = start_github
    travel GithubAuthorization::STATE_TTL + 1.second do
      finish_github(state)
    end
    assert_redirected_to "/session/new"
    assert_requested :post, TOKEN_URL, times: 1
  end

  test "a cancelled authorization signs nobody in" do
    state = start_github

    get "/auth/github/callback", params: { error: "access_denied", state: state }
    assert_redirected_to "/session/new"
    assert_equal "GitHub sign-in was cancelled.", flash[:alert]
    assert_not_requested :post, TOKEN_URL
  end

  test "a cancelled connect returns to Settings" do
    user = create_user(email: "connect@example.com")
    create_account(owner: user)
    sign_in_as(user)
    state = start_github("/settings/github")

    get "/auth/github/callback", params: { error: "access_denied", state: state }
    assert_redirected_to "/settings"
    assert_equal "Connecting GitHub was cancelled.", flash[:alert]
    assert_nil user.reload.github_identity
    assert_not_requested :post, TOKEN_URL
  end

  test "a GitHub email the account rules reject creates nothing" do
    state = start_github
    stub_github(emails: [ { "email" => "#{"m" * 250}@example.com", "primary" => true, "verified" => true } ])

    assert_no_difference [ "User.count", "Account.count", "UserIdentity.count", "Session.count" ] do
      finish_github(state)
    end
    assert_redirected_to "/session/new"
    assert_match "We couldn't create an account from GitHub: Email address is too long", flash[:alert]
  end

  test "a code GitHub refuses, or GitHub being unreachable, signs nobody in" do
    stub_request(:post, TOKEN_URL).to_return(json(error: "bad_verification_code")).then.to_timeout

    2.times do
      state = start_github
      assert_no_difference [ "User.count", "Session.count" ] do
        finish_github(state)
      end
      assert_redirected_to "/session/new"
      assert_match "GitHub didn't confirm your account", flash[:alert]
    end
  end

  test "a signed-in user connects GitHub from Settings and can then sign in with it" do
    user = create_user(email: "connect@example.com")
    create_account(owner: user)
    sign_in_as(user)
    get "/settings"
    assert_select "button", "Connect GitHub"

    state = start_github("/settings/github")
    stub_github(emails: [ { "email" => "personal@example.com", "primary" => true, "verified" => true } ])
    assert_difference "UserIdentity.count", 1 do
      finish_github(state)
    end
    assert_redirected_to "/settings"
    assert_equal [ "4242", "octocat", "personal@example.com" ], user.github_identity.slice(:uid, :login, :email).values
    assert_equal "connect@example.com", user.reload.email_address

    delete "/session"
    finish_github(start_github)
    assert_redirected_to "http://www.example.com/workspace"
  end

  test "connecting refuses a GitHub account another user has connected" do
    other = create_user(email: "other@example.com")
    other.identities.create!(provider: "github", uid: "4242", login: "octocat")
    user = create_user(email: "connect@example.com")
    create_account(owner: user)
    sign_in_as(user)

    state = start_github("/settings/github")
    stub_github
    assert_no_difference "UserIdentity.count" do
      finish_github(state)
    end
    assert_redirected_to "/settings"
    assert_match "connected to another ActiveAgents account", flash[:alert]
    assert_nil user.reload.github_identity
    assert_equal other, UserIdentity.find_by!(uid: "4242").user
  end

  test "connecting the GitHub account already connected refreshes its login" do
    user = create_user(email: "connect@example.com")
    create_account(owner: user)
    user.identities.create!(provider: "github", uid: "4242", login: "old-login")
    sign_in_as(user)

    state = start_github("/settings/github")
    stub_github(login: "new-login")
    assert_no_difference "UserIdentity.count" do
      finish_github(state)
    end
    assert_redirected_to "/settings"
    assert_equal "GitHub is already connected.", flash[:notice]
    assert_equal "new-login", user.github_identity.reload.login
  end

  test "connecting a second GitHub account is refused until the first is disconnected" do
    user = create_user(email: "connect@example.com")
    create_account(owner: user)
    user.identities.create!(provider: "github", uid: "1111", login: "first-login")
    sign_in_as(user)

    state = start_github("/settings/github")
    stub_github(id: 4242, login: "second-login")
    assert_no_difference "UserIdentity.count" do
      finish_github(state)
    end
    assert_redirected_to "/settings"
    assert_equal "Disconnect @first-login before connecting another GitHub account.", flash[:alert]
    assert_equal "1111", user.github_identity.reload.uid
  end

  test "a connect that loses a race for the GitHub account to another user is refused" do
    other = create_user(email: "other@example.com")
    other.identities.create!(provider: "github", uid: "4242", login: "octocat")
    user = create_user(email: "connect@example.com")
    create_account(owner: user)
    sign_in_as(user)
    state = start_github("/settings/github")
    stub_github

    # The other user's connect lands after the controller looked the uid up.
    with_method(UserIdentity, :find_by, ->(*) { nil }) do
      assert_no_difference "UserIdentity.count" do
        finish_github(state)
      end
    end
    assert_redirected_to "/settings"
    assert_equal "That GitHub account is connected to another ActiveAgents account.", flash[:alert]
    assert_nil user.reload.github_identity
  end

  test "a connect completes only for the user and session that started it" do
    first = create_user(email: "first@example.com")
    create_account(owner: first)
    second = create_user(email: "second@example.com")
    create_account(owner: second)
    stub_github

    sign_in_as(first)
    state = start_github("/settings/github")
    delete "/session"
    sign_in_as(second)

    assert_no_difference "UserIdentity.count" do
      finish_github(state)
    end
    assert_redirected_to "/session/new"
    assert_not_requested :post, TOKEN_URL
  end

  test "disconnecting is refused while GitHub is the only way to sign in" do
    user = User.new(email_address: "mona@example.com", email_verified: true)
    user.assign_random_password
    user.save_with_workspace
    user.identities.create!(provider: "github", uid: "4242", login: "octocat")
    stub_github
    finish_github(start_github)

    get "/settings"
    assert_select "button", text: "Disconnect GitHub", count: 0
    delete "/settings/github"
    assert_redirected_to "/settings"
    assert_match "Set a password before disconnecting GitHub", flash[:alert]
    assert user.reload.github_identity

    user.update!(password: "chosen-password", password_confirmation: "chosen-password")
    delete "/settings/github"
    assert_redirected_to "/settings"
    assert_nil user.reload.github_identity
  end

  test "a GitHub-only user emails themselves a password link from Settings, and can disconnect once a password is set" do
    stub_github
    state = start_github
    finish_github(state)
    user = User.find_by!(email_address: "mona@example.com")

    get "/settings"
    assert_select "p", "You haven't set a password, so GitHub is the only way to sign in to this account."
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ user ] do
      post "/settings/password_link"
    end
    assert_redirected_to "/settings"
    assert_equal "We emailed you a link to set a password.", flash[:notice]

    patch "/passwords/#{user.password_reset_token}", params: { password: "chosen-password", password_confirmation: "chosen-password" }
    assert user.reload.password_set?

    post "/session", params: { email_address: user.email_address, password: "chosen-password" }
    get "/settings"
    assert_select "button", "Disconnect GitHub"
    assert_difference "UserIdentity.count", -1 do
      delete "/settings/github"
    end
  end

  test "Settings offers a password link without claiming GitHub is the only sign-in when nothing is connected" do
    post "/registration", params: { email_address: "landing@example.com" }
    user = User.find_by!(email_address: "landing@example.com")
    get "/verify_email", params: { token: user.email_verification_token }
    assert_not user.reload.password_set?

    get "/settings"
    assert_response :success
    assert_select "p", "You haven't chosen a password yet."
    assert_select "p", text: /GitHub is the only way/, count: 0
    assert_select "button", "Email me a link to set a password"
  end

  test "the password link needs a signed-in user" do
    assert_no_enqueued_emails do
      post "/settings/password_link"
    end
    assert_redirected_to "/session/new"
  end

  test "a user with a password disconnects GitHub" do
    user = create_user(email: "connected@example.com")
    create_account(owner: user)
    user.identities.create!(provider: "github", uid: "4242", login: "octocat")
    sign_in_as(user)

    get "/settings"
    assert_select "button", "Disconnect GitHub"
    assert_difference "UserIdentity.count", -1 do
      delete "/settings/github"
    end
    assert_redirected_to "/settings"
  end

  test "GitHub buttons appear only when the GitHub App is configured" do
    get "/session/new"
    assert_select "form[action='/auth/github'] button", "Sign in with GitHub"
    get "/registration/new"
    assert_select "form[action='/auth/github'] button", "Sign up with GitHub"

    ENV.delete("GITHUB_APP_CLIENT_SECRET")
    get "/session/new"
    assert_select "form[action='/auth/github']", count: 0
    get "/registration/new"
    assert_select "form[action='/auth/github']", count: 0
    post "/auth/github"
    assert_response :not_found
  end

  private

  # Starts a GitHub round trip and returns the state GitHub would send back.
  def start_github(path = "/auth/github")
    post path
    assert_response :redirect
    location = URI(response.location)
    assert_equal "https://github.com/login/oauth/authorize", "#{location.scheme}://#{location.host}#{location.path}"
    query = Rack::Utils.parse_query(location.query)
    assert_equal [ CLIENT_ID, CALLBACK_URL ], query.values_at("client_id", "redirect_uri")
    query.fetch("state")
  end

  def finish_github(state, code: "good-code")
    get "/auth/github/callback", params: { code: code, state: state }
  end

  def stub_github(id: 4242, login: "octocat", name: "Mona Octocat", emails: VERIFIED_PRIMARY)
    token = "ghu_#{SecureRandom.hex(8)}"
    stub_request(:post, TOKEN_URL).to_return(json(access_token: token, token_type: "bearer"))
    stub_request(:get, "https://api.github.com/user").with(headers: { "Authorization" => "Bearer #{token}" })
      .to_return(json(id: id, login: login, name: name))
    stub_request(:get, "https://api.github.com/user/emails").with(headers: { "Authorization" => "Bearer #{token}" })
      .to_return(json(emails))
  end

  def json(body)
    { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end
end
