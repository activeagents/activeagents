require "test_helper"

class HuntTest < ActiveSupport::TestCase
  setup do
    @user = create_user
  end

  test "the schedule frequency must be included in the collector's plan" do
    hunt = @user.hunts.new(title: "Seiko Pogue", frequency: "daily")

    assert_not hunt.valid?
    assert_match "aren't included in the Pay as you go plan", hunt.errors[:frequency].first

    hunt.frequency = "weekly"
    assert hunt.valid?
  end

  test "a scheduled hunt gets a next run time; on-demand and paused hunts do not" do
    weekly = create_hunt(@user, frequency: "weekly")
    assert_in_delta 1.week.from_now, weekly.next_run_at, 5

    manual = create_hunt(@user, title: "Leica M6")
    assert_nil manual.next_run_at

    weekly.update!(status: "paused")
    assert_nil weekly.next_run_at

    weekly.update!(status: "active")
    assert_in_delta 1.week.from_now, weekly.next_run_at, 5
  end

  test "due finds active scheduled hunts whose next run time has passed" do
    due = create_hunt(@user, frequency: "weekly")
    due.update_columns(next_run_at: 1.minute.ago)
    create_hunt(@user, title: "Not yet", frequency: "weekly")
    on_demand = create_hunt(@user, title: "On demand")
    on_demand.update_columns(next_run_at: 1.minute.ago)

    assert_equal [ due ], Hunt.due.to_a

    due.update!(status: "paused")
    assert_empty Hunt.due
  end

  test "search queries derive from the brief until the planner agent writes a plan" do
    hunt = create_hunt(@user)

    assert_equal "Patagonia Synchilla Snap-T fleece, 90s", hunt.search_queries.first
    assert_includes hunt.search_queries, "Patagonia synchilla"
    assert hunt.search_queries.size <= 4

    hunt.update!(search_plan: { "queries" => [ "Patagonia Snap-T oval logo made in USA", "synchilla snap t 90s" ] })
    assert_equal [ "Patagonia Snap-T oval logo made in USA", "synchilla snap t 90s" ], hunt.search_queries
  end

  test "the budget is entered in whole currency and stored in cents" do
    hunt = create_hunt(@user, max_price: "1,250.50")
    assert_equal 125_050, hunt.max_price_cents
    assert_equal 1250.5, hunt.max_price
    assert_match "Budget: up to 1250.5 USD", hunt.brief
  end

  test "the plan caps active hunts" do
    3.times { |i| create_hunt(@user, title: "Hunt #{i}") }

    fourth = @user.hunts.new(title: "One too many")
    assert_not fourth.valid?
    assert_match "allows 3 active hunts", fourth.errors[:base].first
  end

  test "run_now! queues a discovery run with the fee fixed at the plan's rate" do
    hunt = create_hunt(@user)

    run = nil
    assert_enqueued_with(job: DiscoveryRunJob) { run = hunt.run_now! }
    assert run.queued?
    assert_equal 199, run.fee_cents
    assert_equal "manual", run.trigger

    Billing.subscribe!(@user, :collector)
    assert_equal 49, hunt.run_now!.fee_cents
  end

  test "plan! keeps nothing when the planner cannot produce a plan" do
    hunt = create_hunt(@user)

    # The mock provider answers in pig latin, which does not fit the
    # planner's declared schema, so the delegation reports invalid_result.
    result = hunt.plan!

    assert_not result[:ok]
    assert_equal "invalid_result", result[:error]
    assert_nil hunt.reload.search_plan
  end
end
