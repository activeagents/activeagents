# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "activeagent.dev serves the open-source lander" do
    host! "activeagent.dev"
    get "/"

    assert_response :success
    assert_match "provider-agnostic", response.body           # OSS hero
    assert_match "See your agents while you build", response.body # dev console section
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

  test "the commercial lander renders the contact form and newsletter" do
    get "/"

    assert_response :success
    assert_match 'id="contact"', response.body
    assert_match "Talk to us about your project", response.body
    assert_match 'action="/leads"', response.body
    assert_match 'id="newsletter"', response.body
  end

  test "service CTAs point at the contact form rather than mailto" do
    get "/"

    assert_response :success
    assert_match "#contact-advisory", response.body
    assert_match "#contact-workshop", response.body
    assert_match "#contact-development", response.body
    assert_match "#contact-enterprise", response.body
    assert_no_match(/mailto:consulting@activeagents\.ai\?subject/, response.body)
  end

  test "the privacy policy renders" do
    get privacy_path

    assert_response :success
    assert_match "Privacy Policy", response.body
  end

  test "the terms of service render" do
    get terms_path

    assert_response :success
    assert_match "Terms of Service", response.body
  end

  test "the footer links to the real legal pages" do
    get "/"

    assert_response :success
    assert_match 'href="/privacy"', response.body
    assert_match 'href="/terms"', response.body
  end
end
