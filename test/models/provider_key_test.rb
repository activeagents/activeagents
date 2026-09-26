# frozen_string_literal: true

require "test_helper"

class ProviderKeyTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @account = create_account(owner: @user)
  end

  test "encrypts the credential at rest" do
    key = @account.provider_keys.create!(provider: "openai", credential: "sk-test-abc123")

    raw = ProviderKey.connection.select_value(
      ProviderKey.sanitize_sql([ "SELECT credential FROM provider_keys WHERE id = ?", key.id ])
    )
    assert_not_includes raw, "sk-test-abc123"
    assert_equal "sk-test-abc123", key.reload.credential
  end

  test "allows one credential per provider per account" do
    @account.provider_keys.create!(provider: "openai", credential: "sk-one")
    duplicate = @account.provider_keys.build(provider: "openai", credential: "sk-two")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:provider], "has already been taken"
  end

  test "rejects unknown providers" do
    key = @account.provider_keys.build(provider: "skynet", credential: "sk-x")

    assert_not key.valid?
    assert_includes key.errors[:provider], "is not included in the list"
  end

  test "ollama requires a URL credential" do
    invalid = @account.provider_keys.build(provider: "ollama", credential: "not-a-url")
    assert_not invalid.valid?
    assert_includes invalid.errors[:credential], "must be an http(s):// URL"

    valid = @account.provider_keys.build(provider: "ollama", credential: "http://localhost:11434/v1")
    assert valid.valid?
  end

  test "generation_options maps keys to access_token and hosts to host" do
    api = @account.provider_keys.create!(provider: "anthropic", credential: "sk-ant-xyz")
    assert_equal({ access_token: "sk-ant-xyz" }, api.generation_options)

    host = @account.provider_keys.create!(provider: "ollama", credential: "http://localhost:11434/v1")
    assert_equal({ host: "http://localhost:11434/v1" }, host.generation_options)
  end

  test "ollama hosts get the /v1 path added and trailing slashes dropped" do
    assert_equal "http://localhost:11434/v1", ProviderKey.normalize_host("http://localhost:11434")
    assert_equal "http://localhost:11434/v1", ProviderKey.normalize_host("http://localhost:11434/")
    assert_equal "http://localhost:11434/v1", ProviderKey.normalize_host(" http://localhost:11434/v1/ ")
    assert_equal "https://ollama.com/v1", ProviderKey.normalize_host("https://ollama.com")
    # An explicit non-default path is left alone (reverse proxies).
    assert_equal "https://ai.example.com/ollama/v1", ProviderKey.normalize_host("https://ai.example.com/ollama/v1")

    key = @account.provider_keys.create!(provider: "ollama", credential: "http://mac-mini.local:11434")
    assert_equal "http://mac-mini.local:11434/v1", key.credential
  end

  test "ollama can carry an optional encrypted api key for remote servers" do
    key = @account.provider_keys.create!(
      provider: "ollama", credential: "https://ollama.com", api_key: " sk-remote-abcd1234 "
    )

    assert key.api_key?
    assert_equal "sk-remote-abcd1234", key.reload.api_key
    assert_equal({ host: "https://ollama.com/v1", access_token: "sk-remote-abcd1234" }, key.generation_options)
    assert_equal "sk-r…1234", key.api_key_hint

    raw = ProviderKey.connection.select_value(
      ProviderKey.sanitize_sql([ "SELECT api_key FROM provider_keys WHERE id = ?", key.id ])
    )
    assert_not_includes raw, "sk-remote-abcd1234"

    key.update!(api_key: "")
    assert_not key.api_key?
    assert_nil key.api_key_hint
    assert_equal({ host: "https://ollama.com/v1" }, key.generation_options)
  end

  test "api keys on key-based providers are ignored" do
    key = @account.provider_keys.create!(provider: "openai", credential: "sk-test", api_key: "unused")

    assert_not key.api_key?
    assert_equal({ access_token: "sk-test" }, key.generation_options)
  end

  test "display_hint masks keys but shows hosts in full" do
    api = @account.provider_keys.create!(provider: "openai", credential: "sk-test-abc123")
    assert_not_includes api.display_hint, "test-abc"
    assert api.display_hint.start_with?("sk-t")
    assert api.display_hint.end_with?("c123")

    host = @account.provider_keys.create!(provider: "ollama", credential: "http://localhost:11434/v1")
    assert_equal "http://localhost:11434/v1", host.display_hint
  end

  test "Account#provider_key_for finds the stored credential" do
    key = @account.provider_keys.create!(provider: "openai", credential: "sk-mine")

    assert_equal key, @account.provider_key_for(:openai)
    assert_equal key, @account.provider_key_for("openai")
    assert_nil @account.provider_key_for(:anthropic)
  end
end
