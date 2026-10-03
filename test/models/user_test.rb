require "test_helper"

class UserTest < ActiveSupport::TestCase
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
