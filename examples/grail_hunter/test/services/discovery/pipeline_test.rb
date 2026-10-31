require "test_helper"

# The whole run against the mock provider, which cannot call tools: the
# search backend's candidates get heuristic scores, and everything else in
# the loop (fee, schedule, digest, trace, persisted conversation) runs for real.
class Discovery::PipelineTest < ActiveSupport::TestCase
  setup do
    ActionAgent::TelemetryTrace.delete_all
    @user = create_user
    @hunt = create_hunt(@user)
  end

  teardown do
    ProductSearch.reset!
  end

  test "a run records findings, books the fee, schedules the hunt and queues a digest" do
    run = @hunt.discovery_runs.create!(user: @user, fee_cents: @user.plan.run_fee_cents)

    Discovery::Pipeline.call(run)
    run.reload

    assert run.completed?, run.error_message
    assert_equal "heuristic", run.scored_by
    assert run.candidate_count.positive?
    assert run.new_findings_count.positive?
    assert run.findings.any? { |finding| finding.title.include?("Synchilla") }
    assert run.findings.all? { |finding| finding.match_score >= Discovery::Pipeline::MIN_HEURISTIC_SCORE }
    assert run.findings.all? { |finding| finding.scored_by == "heuristic" }
    assert run.summary.present?
    assert run.trace_id.present?
    assert run.input_tokens.positive?
    assert_equal "mock", run.provider

    charge = @user.charges.last
    assert_equal 199, charge.amount_cents
    assert_equal run, charge.discovery_run
    assert @hunt.reload.last_run_at.present?
    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob

    # Telemetry and the persisted conversation share the run's trace id.
    ActiveAgent::Telemetry.flush
    trace = ActionAgent::TelemetryTrace.find_by(trace_id: run.trace_id)
    assert trace.present?, "the run's trace should be stored locally"
    assert_equal "HunterAgent", trace.agent_class

    context = run.agent_contexts.last
    assert_equal "HunterAgent", context.agent_name
    assert_equal run.trace_id, context.generations.last.trace_id
  end

  test "a second run only records listings the collector has not seen" do
    first = @hunt.discovery_runs.create!(user: @user, fee_cents: 199)
    Discovery::Pipeline.call(first)
    seen = @hunt.findings.count
    assert seen.positive?

    second = @hunt.discovery_runs.create!(user: @user, fee_cents: 199)
    Discovery::Pipeline.call(second)

    assert second.reload.completed?
    assert_equal 0, second.new_findings_count
    assert_equal seen, @hunt.findings.count
    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob
  end

  test "a plan with no per-run fee books nothing" do
    user = create_user(email: "hunter@example.com", plan: "hunter")
    hunt = create_hunt(user)
    run = hunt.discovery_runs.create!(user: user, fee_cents: user.plan.run_fee_cents)

    Discovery::Pipeline.call(run)

    assert run.reload.completed?
    assert_equal 0, run.fee_cents
    assert_empty user.charges
  end

  test "an error marks the run failed instead of raising, and the schedule moves on" do
    ProductSearch.backend = Class.new(ProductSearch::Backend) {
      def search(*) = raise("marketplace is down")
    }.new
    hunt = create_hunt(@user, title: "Weekly", frequency: "weekly")
    run = hunt.discovery_runs.create!(user: @user, fee_cents: 199)

    assert_nothing_raised { Discovery::Pipeline.call(run) }

    assert run.reload.failed?
    assert_match "marketplace is down", run.error_message
    assert_empty @user.charges
    assert hunt.reload.last_run_at.present?
    assert_in_delta 1.week.from_now, hunt.next_run_at, 5
  end

  test "a search backend error is noted on a completed run" do
    ProductSearch.backend = Class.new(ProductSearch::Backend) {
      def search(*) = raise(ProductSearch::Error, "HTTP 429")
    }.new
    run = @hunt.discovery_runs.create!(user: @user, fee_cents: 199)

    Discovery::Pipeline.call(run)

    assert run.reload.completed?
    assert_equal 0, run.candidate_count
    assert_match "HTTP 429", run.error_message
  end
end
