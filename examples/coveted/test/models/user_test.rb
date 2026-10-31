require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "the first account on an install is the admin, later ones are not" do
    User.delete_all

    first = create_user(email: "first@example.com")
    second = create_user(email: "second@example.com")

    assert first.admin?
    assert_not second.admin?
  end

  test "starts on the default plan and reports the month's charges" do
    user = create_user
    assert_equal Plan.default, user.plan
    assert_not user.subscribed?

    user.charges.create!(kind: "run_fee", amount_cents: 199, description: "Hunt: x")
    user.charges.create!(kind: "run_fee", amount_cents: 199, description: "Hunt: y", status: "voided")

    assert_equal 199, user.month_to_date_cents
  end
end
