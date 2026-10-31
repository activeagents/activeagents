require "test_helper"

class BillingFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as @user
  end

  test "subscribing lowers the run fee, books the month and unlocks daily hunts" do
    post subscribe_billing_path, params: { plan: "collector" }
    assert_redirected_to billing_path

    assert_equal "collector", @user.reload.plan.key
    charge = @user.charges.last
    assert charge.subscription?
    assert_equal 900, charge.amount_cents

    hunt = create_hunt(@user, frequency: "daily")
    assert_equal 49, hunt.run_now!.fee_cents

    get billing_path
    assert_response :success
    assert_match "Your plan", response.body
    assert_match "Collector plan, one month", response.body
  end

  test "a non-subscription plan cannot be subscribed to" do
    post subscribe_billing_path, params: { plan: "pay_as_you_go" }
    assert_redirected_to billing_path
    assert_empty @user.charges
  end

  test "cancelling returns to pay as you go and slows daily hunts to weekly" do
    Billing.subscribe!(@user, :collector)
    hunt = create_hunt(@user, frequency: "daily")

    delete cancel_billing_path
    assert_response :see_other

    assert_equal "pay_as_you_go", @user.reload.plan.key
    assert_equal "weekly", hunt.reload.frequency
  end

  test "run fees are booked once per run and itemised" do
    hunt = create_hunt(@user)
    run = hunt.discovery_runs.create!(user: @user, fee_cents: 199)

    Billing.record_run_fee!(run)
    Billing.record_run_fee!(run)

    assert_equal 1, @user.charges.count
    assert_equal 199, @user.month_to_date_cents

    get billing_path
    assert_match "Hunt: Patagonia Synchilla", response.body
  end
end
