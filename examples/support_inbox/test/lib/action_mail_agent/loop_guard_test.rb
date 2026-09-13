require "test_helper"

# Which inbound mail an agent is allowed to answer. Everything here is a way
# an agent ends up in a conversation with another machine, which is the
# expensive failure mode of putting one on an email address.
class ActionMailAgent::LoopGuardTest < ActiveSupport::TestCase
  test "an ordinary email is answered" do
    assert_nil reason_for(build_mail)
  end

  test "a vacation responder is not" do
    assert_equal :auto_generated, reason_for(build_mail(headers: { "Auto-Submitted" => "auto-replied" }))
    assert_equal :auto_generated, reason_for(build_mail(headers: { "Precedence" => "bulk" }))
    assert_equal :auto_generated, reason_for(build_mail(headers: { "X-Auto-Response-Suppress" => "OOF" }))
    assert_equal :auto_generated, reason_for(build_mail(subject: "Out of office: Dana Scully"))
  end

  test "Auto-Submitted: no is a human saying so" do
    assert_nil reason_for(build_mail(headers: { "Auto-Submitted" => "no" }))
  end

  test "a bounce is not answered" do
    assert_equal :bounce, reason_for(build_mail(from: "MAILER-DAEMON@example.com"))
    assert_equal :bounce, reason_for(build_mail(headers: { "X-Failed-Recipients" => "dana@example.com" }))
  end

  test "a mailing list is not answered" do
    assert_equal :mailing_list, reason_for(build_mail(headers: { "List-Id" => "<rails-talk.example.com>" }))
  end

  test "our own address is never answered, tagged or not" do
    assert_equal :agent_address, reason_for(build_mail(from: "support@example.com"))
    assert_equal :agent_address, reason_for(build_mail(from: "support+f3a9c1d8@example.com"))
  end

  test "a blocked sender is not answered" do
    with_config(blocked_senders: [ /@spam\.example\z/ ]) do
      assert_equal :blocked_sender, reason_for(build_mail(from: "bot@spam.example"))
    end
  end

  test "an empty message is not answered" do
    assert_equal :no_content, reason_for(build_mail(body: "   "))
  end

  test "a conversation a human took over is not answered" do
    ticket = ticket_with(handed_off_at: Time.current)

    assert_equal :handed_off, reason_for(build_mail, conversation: ticket)
  end

  test "a burst of replies on one conversation stops the agent" do
    ticket = ticket_with
    ActionMailAgent.reply_rate_limit.times do |index|
      ticket.replies.create!(author: "Support Agent", body: "Answer #{index}", ai_generated: true)
    end

    assert_equal :reply_limit, reason_for(build_mail, conversation: ticket)
  end

  test "replies outside the window do not count" do
    ticket = ticket_with
    ActionMailAgent.reply_rate_limit.times do |index|
      ticket.replies.create!(
        author: "Support Agent", body: "Answer #{index}", ai_generated: true,
        created_at: (ActionMailAgent.reply_rate_window + 1.minute).ago
      )
    end

    assert_nil reason_for(build_mail, conversation: ticket)
  end

  private

  def reason_for(mail, conversation: nil)
    ActionMailAgent::LoopGuard.new(ActionMailAgent::InboundMessage.new(mail), conversation: conversation).reason
  end

  def build_mail(from: "dana@example.com", subject: "Export to CSV?", body: "Is there a bulk CSV download?", headers: {})
    Mail.new(from: from, to: "support@example.com", subject: subject, body: body).tap do |mail|
      headers.each { |name, value| mail[name] = value }
    end
  end

  def ticket_with(**attributes)
    Ticket.create!(
      subject: "Export to CSV?", body: "Is there a bulk CSV download?",
      customer_email: "dana@example.com", channel: "email", **attributes
    )
  end

  def with_config(**overrides)
    previous = overrides.keys.index_with { |key| ActionMailAgent.public_send(key) }
    overrides.each { |key, value| ActionMailAgent.public_send("#{key}=", value) }
    yield
  ensure
    previous.each { |key, value| ActionMailAgent.public_send("#{key}=", value) }
  end
end
