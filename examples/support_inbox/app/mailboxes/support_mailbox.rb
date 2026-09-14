# The email side of the support inbox: an email arrives, the agent answers it,
# and the answer goes back out on the same thread.
#
# ActionMailAgent::Mailbox runs the exchange (parse, guard, record, answer,
# reply — see lib/action_mail_agent/mailbox.rb). Everything here is the part
# that is specific to this app: a conversation is a Ticket, a message is a
# Reply, and the answer comes from SupportReplyAgent.
class SupportMailbox < ActionMailAgent::Mailbox
  private

  # Ingress retries and customers whose client sends twice both arrive as a
  # second copy of the same Message-Id.
  def duplicate?(inbound)
    return false if inbound.message_id.blank?

    Ticket.exists?(mail_message_id: inbound.message_id) ||
      Reply.exists?(message_id: inbound.message_id)
  end

  # The +tag first, because it survives clients that rewrite headers; the
  # References chain second, for a customer who replied to an address without
  # one (a forward, a colleague looped in, a helpdesk in between).
  def find_conversation(inbound)
    ticket_by_tag(inbound) || ticket_by_references(inbound)
  end

  def ticket_by_tag(inbound)
    tokens = inbound.tags
    return nil if tokens.empty?

    Ticket.find_by(mail_token: tokens)
  end

  def ticket_by_references(inbound)
    return nil if inbound.reference_ids.empty?

    Ticket.find_by(mail_message_id: inbound.reference_ids) ||
      Reply.where(message_id: inbound.reference_ids).order(:created_at).last&.ticket
  end

  # A first email becomes a ticket, and gets triaged on the way in — the same
  # TriageAgent the Triage button runs in the web UI, so an emailed ticket
  # arrives classified instead of waiting for someone to click.
  def open_conversation(inbound)
    ticket = Ticket.create!(
      subject: inbound.bare_subject.presence || "(no subject)",
      body: message_body(inbound),
      customer_email: inbound.from,
      channel: "email",
      mail_message_id: inbound.message_id,
      support_address: support_address_for(inbound)
    )

    ticket.triage!
    escalate_if_urgent(ticket)
    ticket
  end

  def record_inbound(ticket, inbound)
    ticket.replies.create!(
      author: inbound.from,
      body: message_body(inbound),
      inbound: true,
      message_id: inbound.message_id
    )

    # A customer who writes again is waiting on us, whatever the ticket said
    # before.
    ticket.open! unless ticket.open?
  end

  # The agent answer. SupportReplyAgent persists the conversation through
  # solid_agent and carries a telemetry trace id, so this exchange shows up on
  # the dashboard next to every other generation.
  def answer(ticket, inbound)
    SupportReplyAgent.with(ticket: ticket, message: inbound.body).respond.generate_now.message&.content
  end

  def record_reply(ticket, body)
    ticket.replies.create!(
      author: "Support Agent",
      body: body,
      ai_generated: true,
      draft: true
    )
  end

  # Reply#send! is the one door out — the same one the "Send this draft"
  # button uses when delivery_mode is :draft and a person sends it later.
  def deliver(ticket, reply)
    reply.send!
  end

  # One place to see what happened to an email that was not answered. A real
  # deployment pages someone on :handed_off and counts the rest.
  def completed(ticket, reason, reply: nil)
    return if reason.nil? || ticket.nil?

    # Hitting the rate limit means something is wrong that the agent cannot
    # fix by trying again — a loop, or a customer it keeps failing to help.
    ticket.hand_off!(reason: "reply rate limit") if reason == :reply_limit

    Rails.logger.info("[SupportMailbox] ticket ##{ticket.id} not answered: #{reason}")
  end

  # Urgent tickets are a human's, not the agent's. Triage has already run by
  # the time this is called, so the decision uses the same classification the
  # inbox shows.
  def escalate_if_urgent(ticket)
    return unless ticket.priority == "urgent"

    ticket.hand_off!(reason: "triaged urgent")
  end

  # The support address this email was actually sent to, so a reply comes back
  # from the address the customer wrote to. Tagged addresses are untagged
  # first: support+f3a9@ is this ticket's reply address, not an inbox.
  def support_address_for(inbound)
    tagged = inbound.recipients.find { |address| address.start_with?("support@", "support+") }

    ActionMailAgent::Addressing.untagged(tagged || ActionMailAgent.default_from)
  end

  def message_body(inbound)
    return inbound.body if inbound.body.present?
    return "(#{inbound.attachments.size} attachment(s), no message body)" if inbound.attachments.any?

    "(no message body)"
  end
end
