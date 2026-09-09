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

  test "display_hint masks keys but shows hosts in full" do
    api = @account.provider_keys.create!(provider: "openai", credential: "sk-test-abc123")
    assert_not_includes api.display_hint, "test-abc"
    assert api.display_hint.start_with?("sk-t")
    assert api.display_hint.end_with?("c123")

    host = @account.provider_keys.create!(provider: "ollama", credential: "http://localhost:11434/v1")
    assert_equal "http://localhost:11434/v1", host.display_hint
  end

  test "github tokens are accepted, masked and never treated as a host" do
    key = @account.provider_keys.build(provider: "github", credential: "ghp_0123456789abcdefghijklmnopqrstuvwxyz")

    assert key.valid?
    assert_not key.host_based?
    key.save!

    # The dashboard only ever sees the hint: first and last four characters.
    assert_equal "ghp_…wxyz", key.display_hint
    assert_not_includes key.display_hint, "0123456789"
    assert_equal key, @account.provider_key_for("github")
  end

  test "Account#provider_key_for finds the stored credential" do
    key = @account.provider_keys.create!(provider: "openai", credential: "sk-mine")

    assert_equal key, @account.provider_key_for(:openai)
    assert_equal key, @account.provider_key_for("openai")
    assert_nil @account.provider_key_for(:anthropic)
  end
end
