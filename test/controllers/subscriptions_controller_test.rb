# frozen_string_literal: true

require "test_helper"

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(email: "billing@example.com")
    @account = create_account(owner: @user)
    sign_in_as(@user)
  end

  test "checkout returns a JSON error for Inertia requests when the plan has no price" do
    plan = Plan.create!(name: "Pro", slug: "pro", price_cents: 9900)

    post "/subscriptions/checkout",
      params: { plan_id: plan.id, billing_interval: "monthly" },
      headers: { "X-Inertia" => "true" }

    assert_response :unprocessable_entity
    assert_includes json_response["error"], "not available for purchase"
  end

  test "checkout redirects with an alert for plain requests when the plan has no price" do
    plan = Plan.create!(name: "Pro", slug: "pro", price_cents: 9900)

    post "/subscriptions/checkout", params: { plan_id: plan.id }

    assert_redirected_to "/plans"
    assert_equal "This plan is not available for purchase.", flash[:alert]
  end

  test "checkout returns a JSON error for Inertia requests when Stripe is unreachable" do
    plan = Plan.create!(
      name: "Pro", slug: "pro", price_cents: 9900,
      stripe_monthly_price_id: "price_test_123"
    )

    post "/subscriptions/checkout",
      params: { plan_id: plan.id, billing_interval: "monthly" },
      headers: { "X-Inertia" => "true" }

    # No Stripe credentials in test, so Pay raises and the controller must
    # respond with JSON the frontend can surface — not a 500 page
    assert_response :service_unavailable
    assert_includes json_response["error"], "Unable to start checkout"
  end

  test "checkout provisions an account with an owner membership when the user has none" do
    user = create_user(email: "no-account@example.com")
    sign_in_as(user)
    plan = Plan.create!(name: "Pro", slug: "pro", price_cents: 9900)

    assert_difference [ "Account.count", "AccountMembership.count" ], 1 do
      post "/subscriptions/checkout",
        params: { plan_id: plan.id },
        headers: { "X-Inertia" => "true" }
    end

    account = user.owned_accounts.last
    membership = account.account_memberships.find_by(user: user)
    assert_equal "owner", membership.role
  end
end
