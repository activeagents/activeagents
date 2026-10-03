require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "a random password is not one the person chose, and choosing one marks it set" do
    user = User.new(email_address: "random@example.com")
    user.assign_random_password
    user.save!
    assert_not user.reload.password_set?

    user.update!(first_name: "Unchanged")
    assert_not user.reload.password_set?, "saving without a new password leaves it unset"

    user.update!(password: "chosen-password", password_confirmation: "chosen-password")
    assert user.reload.password_set?
  end

  test "a user created with a chosen password has it set" do
    assert create_user.password_set?
  end

  test "a user whose email is already verified gets no verification token" do
    assert_nil create_user(email_verified: true).email_verification_token
    assert User.create!(email_address: "unverified@example.com", password: "password123").email_verification_token.present?
  end

  test "save_with_workspace creates the workspace the user owns, or nothing for an invalid user" do
    user = User.new(email_address: "owner@example.com", password: "password123")
    assert user.save_with_workspace
    assert_equal user, user.primary_account.owner
    assert_equal "owner", user.account_memberships.sole.role

    invalid = User.new(email_address: "not-an-email", password: "password123")
    assert_no_difference [ "User.count", "Account.count", "AccountMembership.count" ] do
      assert_not invalid.save_with_workspace
    end
  end
end
