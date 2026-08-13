# frozen_string_literal: true

require "test_helper"

class Api::ApiKeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
  end

  test "requires an authenticated account" do
    get "/dashboard/api/api_keys"

    # A JSON endpoint says unauthorized rather than redirecting to a form.
    assert_response :unauthorized
  end

  test "create returns the full token exactly once" do
    sign_in_as(@user)

    post "/dashboard/api/api_keys", params: { name: "staging" }, as: :json
    assert_response :created

    token = json_response.dig("api_key", "token")
    assert token.start_with?(ApiKey::TOKEN_PREFIX)
    assert_equal "staging", json_response.dig("api_key", "name")

    # The index never exposes the token again.
    get "/dashboard/api/api_keys"
    assert_response :success
    listed = json_response["api_keys"].first
    assert_nil listed["token"]
    assert_not_includes response.body, token
    assert listed["masked_token"].present?
  end

  test "destroy revokes the key" do
    sign_in_as(@user)
    key = @account.api_keys.create!(name: "old")

    delete "/dashboard/api/api_keys/#{key.id}"
    assert_response :no_content
    assert_not ApiKey.exists?(key.id)
  end

  test "cannot revoke another account's key" do
    other = create_account(owner: create_user)
    foreign_key = other.api_keys.create!(name: "theirs")

    sign_in_as(@user)
    delete "/dashboard/api/api_keys/#{foreign_key.id}"

    assert_response :not_found
    assert ApiKey.exists?(foreign_key.id)
  end
end
