require "test_helper"

class ScheduleHuntsJobTest < ActiveJob::TestCase
  setup do
    @user = create_user(plan: "collector")
  end

  test "queues a run for each due hunt and pushes its schedule forward" do
    due = create_hunt(@user, frequency: "daily")
    due.update_columns(next_run_at: 1.minute.ago)
    create_hunt(@user, title: "Later", frequency: "daily")
    create_hunt(@user, title: "On demand")

    assert_enqueued_jobs 1, only: DiscoveryRunJob do
      assert_equal 1, ScheduleHuntsJob.perform_now
    end

    run = due.discovery_runs.last
    assert_equal "scheduled", run.trigger
    assert_equal 49, run.fee_cents
    assert due.reload.next_run_at > Time.current

    # Nothing is queued twice while that run is still in progress.
    due.update_columns(next_run_at: 1.minute.ago)
    assert_no_enqueued_jobs(only: DiscoveryRunJob) { ScheduleHuntsJob.perform_now }
  end
end
