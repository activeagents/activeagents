require "test_helper"

# Exercises the three AI product features end to end against the gem's
# mock provider (no credentials needed) and asserts the monitoring story:
# every generation stores a telemetry trace whose trace_id also appears on
# the persisted solid_agent generation.
class AgentFeaturesTest < ActionDispatch::IntegrationTest
  setup do
    ActiveAgent::TelemetryTrace.delete_all
    @ticket = Ticket.create!(
      subject: "Charged twice this month",
      body: "My card shows two charges for July. Can you refund the duplicate?",
      customer_email: "dana@example.com"
    )
  end

  test "triage classifies the ticket with safe fallbacks" do
    post triage_ticket_path(@ticket)
    follow_redirect!
    assert_response :success

    @ticket.reload
    assert_includes TriageAgent::CATEGORIES, @ticket.category
    assert_includes TriageAgent::PRIORITIES, @ticket.priority
    assert @ticket.triage_summary.present?
    assert @ticket.triaged_at.present?
  end

  test "draft reply persists a solid_agent conversation correlated with its trace" do
    post draft_reply_ticket_path(@ticket)
    follow_redirect!
    assert_response :success

    draft = @ticket.replies.drafts.last
    assert draft.present?
    assert draft.ai_generated?

    context = @ticket.agent_contexts.last
    assert_equal "SupportReplyAgent", context.agent_name
    generation = context.generations.last
    assert generation.input_tokens.positive?
    assert generation.trace_id.present?

    ActiveAgent::Telemetry.flush
    trace = ActiveAgent::TelemetryTrace.find_by(trace_id: generation.trace_id)
    assert trace.present?, "telemetry trace should share the generation's trace_id"
    assert_equal "SupportReplyAgent", trace.agent_class
  end

  test "summarize stores a thread summary" do
    post summarize_ticket_path(@ticket)
    follow_redirect!

    assert @ticket.reload.ai_summary.present?
  end

  test "sending a draft marks the ticket waiting" do
    post draft_reply_ticket_path(@ticket)
    draft = @ticket.replies.drafts.last

    post send_reply_ticket_reply_path(@ticket, draft)

    assert_not draft.reload.draft?
    assert @ticket.reload.waiting?
  end

  test "inbox lists tickets and the ticket page renders agent activity" do
    post draft_reply_ticket_path(@ticket)

    get tickets_path
    assert_response :success
    assert_match @ticket.subject, response.body

    get ticket_path(@ticket)
    assert_response :success
    assert_match "Persisted agent activity", response.body
  end
end
