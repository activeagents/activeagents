# frozen_string_literal: true

require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "landing page signup creates a user, workspace, and queues Resend sync" do
    email = "newlead#{SecureRandom.hex(4)}@example.com"

    assert_difference -> { User.count }, 1 do
      assert_difference -> { Account.count }, 1 do
        post registration_path, params: { email_address: email }, as: :json
      end
    end

    assert_response :success
    assert json_response["success"]
    assert_equal pending_verification_path, json_response["redirect_url"]

    user = User.find_by(email_address: email)
    assert_equal "landing_page", user.signup_source
    assert_not user.email_verified?
    assert user.accounts.any?
  end

  test "records the signup source when the newsletter form supplies one" do
    email = "news#{SecureRandom.hex(4)}@example.com"
    post registration_path, params: { email_address: email, source: "newsletter" }, as: :json

    assert_response :success
    assert_equal "newsletter", User.find_by(email_address: email).signup_source
  end

  test "queues the Resend audience sync on signup" do
    assert_enqueued_with(job: SyncUserToResendJob) do
      post registration_path, params: { email_address: "sync#{SecureRandom.hex(4)}@example.com" }, as: :json
    end
  end

  test "sends the verification email on signup" do
    assert_enqueued_emails 1 do
      post registration_path, params: { email_address: "verify#{SecureRandom.hex(4)}@example.com" }, as: :json
    end
  end

  test "normalizes the email address" do
    post registration_path, params: { email_address: "  MixedCase#{'X'}@Example.COM  " }, as: :json
    assert_response :success
    assert User.find_by(email_address: "mixedcasex@example.com")
  end

  test "an unverified repeat signup resends verification rather than duplicating" do
    email = "repeat#{SecureRandom.hex(4)}@example.com"
    post registration_path, params: { email_address: email }, as: :json
    assert_response :success

    assert_no_difference -> { User.count } do
      post registration_path, params: { email_address: email }, as: :json
    end

    assert_response :success
    assert json_response["success"]
  end

  test "a verified email is told to sign in instead" do
    email = "verified#{SecureRandom.hex(4)}@example.com"
    user = User.create!(email_address: email, password: "password123")
    user.update!(email_verified: true)

    assert_no_difference -> { User.count } do
      post registration_path, params: { email_address: email }, as: :json
    end

    assert_response :unprocessable_entity
    assert_match(/already registered/i, json_response["error"])
  end

  test "rejects a blank email" do
    assert_no_difference -> { User.count } do
      post registration_path, params: { email_address: "" }, as: :json
    end

    assert_response :unprocessable_entity
  end
end
