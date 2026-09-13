# frozen_string_literal: true

module ActionMailAgent
  # The exchange, in the order it has to happen:
  #
  #   1. normalize the email                    (InboundMessage)
  #   2. find the conversation it belongs to    (find_conversation)
  #   3. refuse to answer machines and loops    (LoopGuard)
  #   4. record what arrived                    (open_conversation / record_inbound)
  #   5. ask the agent for an answer            (answer)
  #   6. record and send it                     (record_reply / deliver)
  #
  # A subclass fills in the hooks with whatever its app calls a conversation —
  # in this demo, a Ticket and its Replies. Nothing here knows about tickets,
  # and nothing in the mailbox subclass has to know about References headers.
  #
  #   class SupportMailbox < ActionMailAgent::Mailbox
  #     def find_conversation(inbound) = Ticket.find_by(mail_token: inbound.tags.first)
  #     ...
  #   end
  #
  # Every path through this method ends with the email on record. Mail the
  # agent declines to answer is the mail a support team most needs to see.
  class Mailbox < ActionMailbox::Base
    # Broadcast for each processed email, whatever the outcome. The demo's
    # tests assert on it, and it is the seam a host would use to page someone
    # when the agent stops answering.
    NOTIFICATION = "exchange.action_mail_agent"

    def process
      return if duplicate?(inbound)

      conversation = find_conversation(inbound)
      reason = LoopGuard.new(inbound, conversation: conversation).reason

      # A bounce or a vacation responder with no conversation behind it opens
      # nothing: a support queue full of tickets from MAILER-DAEMON is how
      # this goes wrong in practice.
      if conversation.nil?
        return publish(nil, reason) if reason

        conversation = open_conversation(inbound)
      else
        record_inbound(conversation, inbound)
      end

      return finish(conversation, reason) if reason

      # Opening a conversation can decide it is not the agent's — a triage
      # rule, a known-difficult customer, an account in arrears. That decision
      # is made in the hook above, so it is read back here rather than
      # duplicated in the guard.
      return finish(conversation, :handed_off) if handed_off?(conversation)
      return finish(conversation, :delivery_off) if ActionMailAgent.delivery_mode == :off

      text = answer(conversation, inbound)
      return finish(conversation, :no_answer) if text.blank?

      reply = record_reply(conversation, text)

      # The agent can decide mid-answer that a human should take this one (see
      # the hand_off tool in SupportReplyAgent) — that decision is only
      # visible after the generation, so the reply is written down and left
      # unsent rather than never written at all.
      return finish(conversation, :handed_off) if handed_off?(conversation)
      return finish(conversation, :draft_mode, reply: reply) if ActionMailAgent.delivery_mode == :draft

      deliver(conversation, reply)
      finish(conversation, nil, reply: reply)
    end

    # The email being processed, normalized.
    # @return [ActionMailAgent::InboundMessage]
    def inbound
      @inbound ||= InboundMessage.new(mail, inbound_email: inbound_email)
    end

    private

    # ---- Hooks --------------------------------------------------------------

    # Has this exact email been processed before? Retried ingress and a
    # customer's mail client sending twice both arrive as a second copy with
    # the same Message-Id.
    def duplicate?(inbound)
      false
    end

    # @return [Object, nil] the conversation this email continues
    def find_conversation(inbound)
      raise NotImplementedError, "#{self.class} must implement #find_conversation"
    end

    # @return [Object] a new conversation for an email that continues nothing
    def open_conversation(inbound)
      raise NotImplementedError, "#{self.class} must implement #open_conversation"
    end

    # Record a follow-up on an existing conversation. Opening one is expected
    # to record the first message itself.
    def record_inbound(conversation, inbound)
      nil
    end

    # @return [String, nil] the agent's answer; nil or blank sends nothing
    def answer(conversation, inbound)
      raise NotImplementedError, "#{self.class} must implement #answer"
    end

    # @return [Object] the persisted reply, handed back to #deliver
    def record_reply(conversation, body)
      raise NotImplementedError, "#{self.class} must implement #record_reply"
    end

    def deliver(conversation, reply)
      raise NotImplementedError, "#{self.class} must implement #deliver"
    end

    # Called once per email with the outcome: nil when it was answered, a
    # LoopGuard reason (or :no_answer, :draft_mode, :handed_off, :delivery_off)
    # when it was not.
    def completed(conversation, reason, reply: nil)
      nil
    end

    def handed_off?(conversation)
      conversation.respond_to?(:handed_off?) && conversation.reload.handed_off?
    end

    # ---- Outcome ------------------------------------------------------------

    def finish(conversation, reason, reply: nil)
      completed(conversation, reason, reply: reply)
      publish(conversation, reason, reply: reply)
    end

    def publish(conversation, reason, reply: nil)
      ActiveSupport::Notifications.instrument(
        NOTIFICATION,
        mailbox: self.class.name,
        conversation: conversation&.to_gid_param,
        message_id: inbound.message_id,
        from: inbound.from,
        reason: reason,
        replied: reply.present? && reason.nil?
      )

      Rails.logger.info(
        "[ActionMailAgent] #{self.class.name} #{inbound.from} " \
        "#{reason ? "skipped(#{reason})" : "answered"} message_id=#{inbound.message_id}"
      )

      nil
    end
  end
end
