# frozen_string_literal: true

require "test_helper"

class Api::ProviderKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
  end

  test "requires an authenticated account" do
    get "/dashboard/api/provider_keys"

    # A JSON endpoint says unauthorized rather than redirecting to a form.
    assert_response :unauthorized
  end

  test "index lists every supported provider without exposing credentials" do
    @account.provider_keys.create!(provider: "openai", credential: "sk-secret-abc123")
    sign_in_as(@user)

    get "/dashboard/api/provider_keys"
    assert_response :success

    rows = json_response["provider_keys"]
    assert_equal ProviderKey::PROVIDERS.sort, rows.map { |r| r["provider"] }.sort

    openai = rows.find { |r| r["provider"] == "openai" }
    assert openai["configured"]
    assert_not_includes response.body, "sk-secret-abc123"

    ollama = rows.find { |r| r["provider"] == "ollama" }
    assert ollama["host_based"]
    assert_not ollama["configured"]
  end

  test "create upserts the credential for a provider" do
    sign_in_as(@user)

    post "/dashboard/api/provider_keys", params: { provider: "anthropic", credential: "sk-ant-first" }, as: :json
    assert_response :created

    post "/dashboard/api/provider_keys", params: { provider: "anthropic", credential: "sk-ant-second" }, as: :json
    assert_response :created

    assert_equal 1, @account.provider_keys.where(provider: "anthropic").count
    assert_equal "sk-ant-second", @account.provider_key_for(:anthropic).credential
  end

  test "create accepts an ollama host URL and rejects a non-URL" do
    sign_in_as(@user)

    post "/dashboard/api/provider_keys", params: { provider: "ollama", credential: "http://localhost:11434/v1" }, as: :json
    assert_response :created
    assert_equal "http://localhost:11434/v1", json_response.dig("provider_key", "hint")

    post "/dashboard/api/provider_keys", params: { provider: "ollama", credential: "localhost:11434" }, as: :json
    assert_response :unprocessable_entity
  end

  test "rejects unknown providers" do
    sign_in_as(@user)

    post "/dashboard/api/provider_keys", params: { provider: "skynet", credential: "sk-x" }, as: :json
    assert_response :unprocessable_entity
  end

  test "destroy removes the credential" do
    @account.provider_keys.create!(provider: "openai", credential: "sk-old")
    sign_in_as(@user)

    delete "/dashboard/api/provider_keys/openai"
    assert_response :no_content
    assert_nil @account.provider_key_for(:openai)
  end
end
