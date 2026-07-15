# frozen_string_literal: true

require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(email: "onboarding@example.com")
    @user.update!(email_verified: true)
    @account = create_account(owner: @user)
    sign_in_as(@user)
  end

  test "completing profile with the free plan lands on the dashboard" do
    patch "/complete_profile", params: {
      user: profile_params,
      plan_slug: "free"
    }

    assert_redirected_to "/dashboard"
  end

  test "completing profile with a paid plan does not silently land on the free dashboard" do
    Plan.create!(
      name: "Pro", slug: "pro", price_cents: 9900,
      stripe_monthly_price_id: "price_test_123"
    )

    patch "/complete_profile", params: {
      user: profile_params,
      plan_slug: "pro"
    }

    # Stripe is not configured in test, so checkout session creation fails and
    # the controller falls back to the dashboard — the selection must not
    # leave a dangling session value behind
    assert_redirected_to "/dashboard"
    assert_nil session[:selected_plan_slug]
  end

  test "paid plan selection without a Stripe price falls back to the dashboard" do
    Plan.create!(name: "Pro", slug: "pro", price_cents: 9900)

    patch "/complete_profile", params: {
      user: profile_params,
      plan_slug: "pro"
    }

    assert_redirected_to "/dashboard"
  end

  private

  def profile_params
    {
      first_name: "Test",
      last_name: "User",
      company_name: "Acme",
      job_title: "Engineer",
      password: "password123",
      password_confirmation: "password123"
    }
  end
end
