# frozen_string_literal: true

require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @account = create_account(owner: @user)
  end

  test "generates a prefixed token on create" do
    key = @account.api_keys.create!(name: "production")

    assert key.token.start_with?(ApiKey::TOKEN_PREFIX)
    assert_operator key.token.length, :>, 20
    assert_equal key.token.first(7), key.token_prefix
  end

  test "tokens are unique across keys" do
    first = @account.api_keys.create!(name: "one")
    second = @account.api_keys.create!(name: "two")

    assert_not_equal first.token, second.token
  end

  test "encrypts the token at rest" do
    key = @account.api_keys.create!(name: "production")

    ciphertext = key.ciphertext_for(:token)
    assert_not_equal key.token, ciphertext

    raw = ApiKey.connection.select_value(
      ApiKey.sanitize_sql([ "SELECT token FROM api_keys WHERE id = ?", key.id ])
    )
    assert_not_includes raw, key.token
  end

  test "authenticate finds the key by plaintext token" do
    key = @account.api_keys.create!(name: "production")

    assert_equal key, ApiKey.authenticate(key.token)
    assert_nil ApiKey.authenticate("aa_notarealtoken")
    assert_nil ApiKey.authenticate(nil)
    assert_nil ApiKey.authenticate("")
  end

  test "masked_token hides the token body" do
    key = @account.api_keys.create!(name: "production")

    assert_not_includes key.masked_token, key.token
    assert key.masked_token.start_with?(key.token_prefix)
    assert key.masked_token.end_with?(key.token.last(4))
  end

  test "requires a name" do
    key = @account.api_keys.build

    assert_not key.valid?
    assert_includes key.errors[:name], "can't be blank"
  end

  test "touch_last_used! throttles writes" do
    key = @account.api_keys.create!(name: "production")

    key.touch_last_used!
    first_seen = key.reload.last_used_at
    assert first_seen.present?

    key.touch_last_used!
    assert_equal first_seen, key.reload.last_used_at
  end
end
