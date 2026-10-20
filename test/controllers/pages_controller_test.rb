# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "activeagent.dev serves the open-source lander" do
    host! "activeagent.dev"
    get "/"

    assert_response :success
    assert_match "provider-agnostic", response.body           # OSS hero
    assert_match "See your agents while you build", response.body # dev console section
    assert_match "Free, and free forever.", response.body     # the gems
    assert_match "Release notes, in your inbox.", response.body # newsletter signup
    assert_match "Agents are controllers", response.body      # shared framework section
    assert_no_match(/Pro Platform/, response.body)            # no hosted pricing
    assert_match "https://activeagents.ai", response.body     # cross-link to commercial
  end

  test "www.activeagent.dev also serves the open-source lander" do
    host! "www.activeagent.dev"
    get "/"

    assert_response :success
    assert_match "See your agents while you build", response.body
  end

  test "the default host serves the commercial lander" do
    get "/"

    assert_response :success
    assert_match "See everything it does", response.body             # hero
    assert_match "Three gems. One wire format.", response.body       # pipeline
    assert_match "See inside every agent decision", response.body    # dashboard
    assert_match "Production observability for Rails AI agents", response.body
    assert_match "Pro Platform", response.body
    assert_match "https://activeagent.dev", response.body     # cross-link to OSS
  end

  test "activeagent.pro serves the commercial lander" do
    host! "activeagent.pro"
    get "/"

    assert_response :success
    assert_match "Pro Platform", response.body
  end

  test "site param forces a variant for previewing" do
    get "/", params: { site: "oss" }
    assert_match "See your agents while you build", response.body

    host! "activeagent.dev"
    get "/", params: { site: "commercial" }
    assert_match "Pro Platform", response.body
  end

  test "a visitor sees Sign In in the bar and the menu" do
    get "/"

    assert_response :success
    assert_select "header .nav-actions a[href='/dashboard']", "Sign In"
    assert_select "header .nav-menu a[href='/dashboard']", "Sign In"
    assert_select "header .nav-menu a[href='/registration/new']", "Start Free"
  end

  test "a signed-in visitor is sent from the root to their dashboard" do
    user = create_user
    create_account(owner: user)
    sign_in_as(user)

    get "/"
    assert_redirected_to "/dashboard"
  end

  test "a signed-in visitor whose email is not verified is sent to verify it" do
    user = User.create!(email_address: "new@example.com", password: "password123")
    post "/session", params: { email_address: user.email_address, password: "password123" }

    get "/"
    assert_redirected_to "/pending_verification"
  end

  test "a signed-in visitor can still look at the lander, where the bar offers the dashboard" do
    user = create_user
    create_account(owner: user)
    sign_in_as(user)

    get "/", params: { site: "commercial" }
    assert_response :success
    assert_select "header .nav-actions a[href='/dashboard']", "Dashboard"
    assert_select "header .nav-menu a[href='/dashboard']", "Go to your dashboard"
    assert_select "header a", text: "Sign In", count: 0

    get "/", params: { site: "oss" }
    assert_response :success
    assert_match "See your agents while you build", response.body
  end
end
