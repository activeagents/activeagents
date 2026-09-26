# frozen_string_literal: true

require "test_helper"
require_relative "../../support/fake_ollama_server"

class Api::ProviderKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
  end

  test "requires an authenticated account" do
    get "/dashboard/api/provider_keys", as: :json

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

  test "create normalizes a bare ollama host and stores an optional masked api key" do
    sign_in_as(@user)

    post "/dashboard/api/provider_keys",
      params: { provider: "ollama", credential: "https://ollama.com", api_key: "sk-remote-abcd1234" }, as: :json
    assert_response :created

    row = json_response["provider_key"]
    assert_equal "https://ollama.com/v1", row["hint"]
    assert row["api_key_configured"]
    assert_equal "sk-r…1234", row["api_key_hint"]
    assert_not_includes response.body, "sk-remote-abcd1234"

    # Omitting api_key keeps the stored one; an empty api_key clears it.
    post "/dashboard/api/provider_keys", params: { provider: "ollama", credential: "https://ollama.com/v1" }, as: :json
    assert_equal "sk-remote-abcd1234", @account.provider_key_for(:ollama).api_key

    post "/dashboard/api/provider_keys", params: { provider: "ollama", credential: "https://ollama.com/v1", api_key: "" }, as: :json
    assert_nil @account.provider_key_for(:ollama).api_key
    assert_not json_response.dig("provider_key", "api_key_configured")
  end

  test "test probes a submitted host and key without saving them" do
    sign_in_as(@user)

    FakeOllamaServer.run(body: { data: [ { id: "qwen3:4b" } ] }.to_json) do |server|
      post "/dashboard/api/provider_keys/test",
        params: { provider: "ollama", credential: server.host, api_key: "sk-x" }, as: :json
      assert_response :success

      assert_equal "/v1/models", server.requests.first[:path]
      assert_equal "Bearer sk-x", server.requests.first[:headers]["Authorization"]
    end

    assert json_response["ok"]
    assert_equal %w[qwen3:4b], json_response["models"]
    assert_kind_of Integer, json_response["latency_ms"]
    assert_nil @account.provider_key_for(:ollama)
  end

  test "test falls back to the stored host and key" do
    FakeOllamaServer.run(status: 401, body: "") do |server|
      @account.provider_keys.create!(provider: "ollama", credential: server.host, api_key: "sk-stored")
      sign_in_as(@user)

      post "/dashboard/api/provider_keys/test", params: { provider: "ollama" }, as: :json
      assert_response :success

      assert_equal "Bearer sk-stored", server.requests.first[:headers]["Authorization"]
    end

    assert_not json_response["ok"]
    assert_match(/401/, json_response["error"])
  end

  test "test reports no host when nothing is configured and rejects key-based providers" do
    sign_in_as(@user)

    post "/dashboard/api/provider_keys/test", params: { provider: "ollama" }, as: :json
    assert_response :success
    assert_not json_response["ok"]
    assert_equal "No host configured", json_response["error"]

    post "/dashboard/api/provider_keys/test", params: { provider: "openai" }, as: :json
    assert_response :unprocessable_entity
  end
end
