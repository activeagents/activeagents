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
end
