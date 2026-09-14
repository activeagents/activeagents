require "test_helper"
require "action_mailbox/test_helper"

# The email side of the inbox, end to end: an email arrives through
# ActionMailbox, the agent answers it (mock provider — no credentials), and
# the answer goes back out through ActionMailer threaded onto the same
# conversation.
class SupportMailboxTest < ActiveSupport::TestCase
  include ActionMailbox::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
    ActionAgent::TelemetryTrace.delete_all
  end

  test "a first email opens a triaged ticket and the agent answers it" do
    receive(
      from: "Dana Scully <dana@example.com>",
      subject: "Charged twice this month",
      body: "My card shows two charges for July. Can you refund the duplicate?"
    )

    ticket = Ticket.sole
    assert_equal "email", ticket.channel
    assert_equal "dana@example.com", ticket.customer_email
    assert_equal "Charged twice this month", ticket.subject
    assert ticket.mail_token.present?, "a ticket needs a token for replies to come back on"
    assert ticket.triaged_at.present?, "an emailed ticket is triaged on arrival"

    answer = ticket.replies.outbound.sole
    assert answer.ai_generated?
    assert answer.delivered?
    assert_not answer.draft?

    email = ActionMailer::Base.deliveries.sole
    assert_equal [ "dana@example.com" ], email.to
    assert_equal [ "support@example.com" ], email.from
    assert_equal "Re: Charged twice this month", email.subject
    assert_equal [ ticket.reply_address ], email.reply_to
    assert_equal "auto-replied", email["Auto-Submitted"].to_s
    assert_equal ticket.mail_message_id, email.in_reply_to
  end

  test "a reply to the reply address continues the same ticket" do
    receive(subject: "Export to CSV?", body: "Is there a bulk CSV download?")
    ticket = Ticket.sole
    first_answer = ticket.replies.outbound.sole

    receive(
      to: ticket.reply_address,
      subject: "Re: Export to CSV?",
      body: "Thanks! Does that include archived records?",
      in_reply_to: "<#{first_answer.message_id}>"
    )

    assert_equal 1, Ticket.count, "a reply must not open a second ticket"
    ticket.reload
    assert_equal "Thanks! Does that include archived records?", ticket.replies.inbound.sole.body
    assert_equal 2, ticket.replies.outbound.count
    assert_equal 2, ActionMailer::Base.deliveries.size
  end

  test "a reply threads by References when the tagged address is gone" do
    receive(subject: "Password reset", body: "The reset email never arrives.")
    ticket = Ticket.sole
    answer = ticket.replies.outbound.sole

    receive(
      to: "support@example.com",
      subject: "Re: Password reset",
      body: "Still nothing, I checked spam.",
      references: "<#{ticket.mail_message_id}> <#{answer.message_id}>"
    )

    assert_equal 1, Ticket.count
    assert_equal 1, ticket.reload.replies.inbound.count
  end

  test "the quoted thread is stripped before the agent sees it" do
    receive(subject: "Export to CSV?", body: "Is there a bulk CSV download?")
    ticket = Ticket.sole

    receive(
      to: ticket.reply_address,
      subject: "Re: Export to CSV?",
      body: <<~BODY
        Perfect, thank you.

        On Mon, Sep 1, 2025 at 9:03 AM Support <support@example.com> wrote:
        > You can export everything from Settings.
        > -- The Support Team
      BODY
    )

    assert_equal "Perfect, thank you.", ticket.reload.replies.inbound.sole.body
  end

  test "an auto-reply is recorded but never answered" do
    receive(subject: "Export to CSV?", body: "Is there a bulk CSV download?")
    ticket = Ticket.sole
    ActionMailer::Base.deliveries.clear

    receive(
      to: ticket.reply_address,
      subject: "Out of office",
      body: "I am away until Monday.",
      headers: { "Auto-Submitted" => "auto-replied" }
    )

    assert_equal 1, ticket.reload.replies.inbound.count, "the message is still on record"
    assert_equal 1, ticket.replies.outbound.count, "but the agent does not answer a machine"
    assert_empty ActionMailer::Base.deliveries
  end

  test "a bounce never opens a ticket" do
    receive(
      from: "MAILER-DAEMON@example.com",
      subject: "Undeliverable: Charged twice",
      body: "Your message could not be delivered."
    )

    assert_equal 0, Ticket.count
    assert_empty ActionMailer::Base.deliveries
  end

  test "the same email arriving twice is answered once" do
    source = build_mail(subject: "Export to CSV?", body: "Is there a bulk CSV download?").to_s
    inbound_email = receive_inbound_email_from_source(source)

    # ActionMailbox refuses the second copy at the ingress, on the unique
    # Message-Id — until the first one is incinerated, which is what makes a
    # late resend reach the mailbox at all.
    assert_nil create_inbound_email_from_source(source)
    inbound_email.destroy!

    receive_inbound_email_from_source(source)

    assert_equal 1, Ticket.count, "the mailbox recognises a Message-Id it has already answered"
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "an urgent ticket is handed to a human instead of answered" do
    ticket = nil

    stub_triage_priority("urgent") do
      receive(subject: "Production is down", body: "Everything is 500ing since the deploy.")
      ticket = Ticket.sole
    end

    assert ticket.handed_off?
    assert_equal "triaged urgent", ticket.handoff_reason
    assert_empty ticket.replies.outbound
    assert_empty ActionMailer::Base.deliveries
  end

  test "the agent stops answering, and hands off, when replies burst" do
    receive(subject: "Export to CSV?", body: "Is there a bulk CSV download?")
    ticket = Ticket.sole

    # A burst of answers on one ticket inside the window is what a loop looks
    # like from this end, whatever the other end's headers claim.
    (ActionMailAgent.reply_rate_limit - 1).times do |index|
      ticket.replies.create!(author: "Support Agent", body: "Answer #{index}", ai_generated: true)
    end

    ActionMailer::Base.deliveries.clear
    receive(to: ticket.reply_address, subject: "Re: Export to CSV?", body: "Please advise.")

    assert_empty ActionMailer::Base.deliveries
    assert_equal 1, ticket.reload.replies.inbound.count, "the message is still on record"
    assert ticket.handed_off?, "a rate-limited ticket belongs to a human"
  end

  test "draft mode records the answer and sends nothing" do
    with_delivery_mode(:draft) do
      receive(subject: "Export to CSV?", body: "Is there a bulk CSV download?")
    end

    answer = Ticket.sole.replies.outbound.sole
    assert answer.draft?, "a drafted answer waits for a human"
    assert_not answer.delivered?
    assert_empty ActionMailer::Base.deliveries
  end

  test "every processed email is instrumented with what happened to it" do
    outcomes = []
    subscriber = ActiveSupport::Notifications.subscribe(ActionMailAgent::Mailbox::NOTIFICATION) do |*, payload|
      outcomes << payload.slice(:reason, :replied)
    end

    receive(subject: "Export to CSV?", body: "Is there a bulk CSV download?")
    receive(from: "MAILER-DAEMON@example.com", subject: "Undeliverable", body: "Message not delivered.")

    assert_equal [ { reason: nil, replied: true }, { reason: :bounce, replied: false } ], outcomes
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "a draft a person sends from the inbox goes out by email on the thread" do
    with_delivery_mode(:draft) do
      receive(subject: "Export to CSV?", body: "Is there a bulk CSV download?")
    end
    ticket = Ticket.sole
    draft = ticket.replies.outbound.sole

    draft.send!

    email = ActionMailer::Base.deliveries.sole
    assert_equal [ "dana@example.com" ], email.to
    assert_equal ticket.mail_message_id, email.in_reply_to
    assert_equal draft.message_id, email.message_id
    assert draft.reload.delivered?
    assert_not draft.draft?
    assert ticket.reload.waiting?
  end

  test "the answer is persisted as a solid_agent conversation carrying its trace" do
    receive(subject: "Export to CSV?", body: "Is there a bulk CSV download?")
    ticket = Ticket.sole

    context = ticket.agent_contexts.sole
    assert_equal "SupportReplyAgent", context.agent_name
    generation = context.generations.last
    assert generation.trace_id.present?

    ActiveAgent::Telemetry.flush
    trace = ActionAgent::TelemetryTrace.find_by(trace_id: generation.trace_id)
    assert trace.present?, "the emailed answer should show up on the dashboard like any other generation"
  end

  private

  def build_mail(from: "dana@example.com", to: "support@example.com", subject:, body:, headers: {}, **fields)
    Mail.new(
      from: from,
      to: to,
      subject: subject,
      body: body,
      message_id: "<#{SecureRandom.uuid}@example.com>",
      **fields
    ).tap do |mail|
      headers.each { |name, value| mail[name] = value }
    end
  end

  def receive(**options)
    receive_inbound_email_from_source(build_mail(**options).to_s)
  end

  def with_delivery_mode(mode)
    previous = ActionMailAgent.delivery_mode
    ActionMailAgent.delivery_mode = mode
    yield
  ensure
    ActionMailAgent.delivery_mode = previous
  end

  # TriageAgent runs against the mock provider, which does not return JSON, so
  # a ticket normally lands on the neutral defaults of Ticket#apply_triage!.
  # Staging an urgent classification means standing in for the generation,
  # which is the one thing in this flow a test cannot get from the mock.
  def stub_triage_priority(priority)
    classification = { category: "bug", priority: priority, sentiment: "negative", summary: "Outage" }.to_json
    response = Struct.new(:message).new(Struct.new(:content).new(classification))
    generation = Struct.new(:generate_now).new(response)
    agent = Struct.new(:triage).new(generation)

    TriageAgent.define_singleton_method(:with) { |**| agent }
    yield
  ensure
    # `with` comes from ActiveAgent::Base; removing the singleton method puts
    # the inherited one back rather than deleting it.
    TriageAgent.singleton_class.remove_method(:with)
  end
end
