# frozen_string_literal: true

# Email as an agent transport: ActionMailbox receives, an Active Agent
# answers, ActionMailer replies on the same thread.
#
#   class SupportMailbox < ActionMailAgent::Mailbox
#     def answer(inbound) = SupportReplyAgent.with(...).respond.generate_now
#   end
#
# Everything under `lib/action_mail_agent` is deliberately app-agnostic: it
# knows about email, conversations and agents, and nothing about tickets. That
# is the seam this demo is drawing — if the shape holds up, this directory is
# what gets extracted as an `actionmailagent` gem, and the app keeps only the
# mailbox subclass in `app/mailboxes` that maps a conversation onto a Ticket.
#
# What lives here is the part every email/agent integration has to rebuild:
#
#   * BodyParser    — reduce a reply chain to the sentence the customer wrote
#   * Addressing    — +tag reply addresses, so a reply finds its conversation
#   * InboundMessage— one normalized view of a Mail::Message
#   * LoopGuard     — never answer a bounce, a vacation responder, or yourself
#   * Mailbox       — the exchange: parse, guard, answer, reply, record
#
module ActionMailAgent
  # Delivery modes for a generated reply.
  #
  #   :auto  — deliver it (the default)
  #   :draft — record it, deliver nothing. What a team putting an agent in
  #            front of real customers wants on day one: the replies are there
  #            to read, no customer receives one.
  #   :off   — do not generate at all; inbound mail is only recorded.
  DELIVERY_MODES = %i[auto draft off].freeze

  class << self
    # From address for replies, when the conversation does not name one. The
    # address the customer wrote to wins over this: a reply should come back
    # from the address it was sent to.
    # @return [String]
    attr_accessor :default_from

    # Domain for the +tag reply addresses that thread a conversation.
    # Defaults to the domain of the address the reply is sent from.
    # @return [String, nil]
    attr_accessor :reply_to_domain

    # @return [Symbol] one of DELIVERY_MODES
    attr_reader :delivery_mode

    def delivery_mode=(mode)
      mode = mode.to_sym
      unless DELIVERY_MODES.include?(mode)
        raise ArgumentError, "Unknown delivery mode #{mode.inspect} (expected #{DELIVERY_MODES.join(", ")})"
      end

      @delivery_mode = mode
    end

    # How many replies the agent may send to one conversation inside
    # reply_rate_window. The backstop against two autoresponders talking to
    # each other until someone notices the bill — deliberately a rate rather
    # than a count of replies "since the customer last wrote", because in a
    # loop the other end *is* writing back, and that counter would reset on
    # every bounce of the ball.
    # @return [Integer]
    attr_accessor :reply_rate_limit

    # The window reply_rate_limit is measured over. Long enough to catch a
    # loop, short enough that a customer working through a problem over a week
    # is never told to wait.
    # @return [ActiveSupport::Duration]
    attr_accessor :reply_rate_window

    # How many past messages of a conversation are handed to the agent.
    # @return [Integer]
    attr_accessor :history_limit

    # Addresses the agent itself posts from. Mail arriving from one of them is
    # never answered — that is the shape a loop takes when a support address
    # ends up subscribed to its own outbox.
    # @return [Array<String, Regexp>]
    attr_accessor :agent_addresses

    # Senders never answered: addresses, or patterns matched against the whole
    # address (`/@example\.test\z/`).
    # @return [Array<String, Regexp>]
    attr_accessor :blocked_senders

    # Marker rendered into outgoing replies and treated as a quote boundary on
    # the way back in, for clients whose quoting the parser cannot recognise.
    # @return [String, nil]
    attr_accessor :reply_delimiter

    # Called when a conversation hands off to a human:
    # `->(conversation, reason) { ... }`. This layer does not decide what a
    # handoff means for a given team — only that the conversation reached one.
    # @return [Proc, nil]
    attr_accessor :handoff_notifier

    def configure
      yield self
    end

    # Runs the handoff notifier, if one is configured. A notifier that raises
    # must not lose the exchange: the conversation is already on record by
    # then, and the inbound email would otherwise be retried and answered
    # twice.
    def notify_handoff(conversation, reason)
      handoff_notifier&.call(conversation, reason)
    rescue StandardError => error
      Rails.logger&.error("[ActionMailAgent] handoff notifier failed: #{error.class}: #{error.message}")
      nil
    end
  end

  self.default_from = "support@example.com"
  self.delivery_mode = :auto
  self.reply_rate_limit = 5
  self.reply_rate_window = 1.hour
  self.history_limit = 20
  self.agent_addresses = []
  self.blocked_senders = []
end
