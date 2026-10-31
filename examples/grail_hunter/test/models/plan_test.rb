require "test_helper"

class PlanTest < ActiveSupport::TestCase
  test "plans load from config/plans.yml in order, default first" do
    assert_equal %w[pay_as_you_go collector hunter], Plan.keys
    assert_equal Plan.find(:pay_as_you_go), Plan.default
    assert_not Plan.default.subscription?
    assert Plan.find(:hunter).subscription?
  end

  test "a higher plan lowers the per-run fee and unlocks faster schedules" do
    payg, collector, hunter = Plan.all

    assert payg.run_fee_cents > collector.run_fee_cents
    assert collector.run_fee_cents > hunter.run_fee_cents
    assert hunter.free_runs?

    assert payg.allows_frequency?("weekly")
    assert_not payg.allows_frequency?("daily")
    assert collector.allows_frequency?("daily")
    assert_not collector.allows_frequency?("hourly")
    assert hunter.allows_frequency?("hourly")
    assert_equal "hourly", hunter.fastest_frequency
    assert payg < collector
  end

  test "an unknown plan raises" do
    assert_raises(ArgumentError) { Plan.find(:platinum) }
    assert_nil Plan.find_by(:platinum)
  end
end
