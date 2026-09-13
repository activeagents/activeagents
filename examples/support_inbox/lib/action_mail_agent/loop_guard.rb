# frozen_string_literal: true

module ActionMailAgent
  # Decides whether an inbound email may be answered by an agent.
  #
  # An agent that answers everything it receives will, sooner or later, answer
  # a vacation responder that answers it back. The cost of that mistake is
  # measured in provider bills and customer trust, and it is not hypothetical:
  # it is the reason RFC 3834 exists.
  #
  #   guard = ActionMailAgent::LoopGuard.new(inbound, conversation: ticket)
  #   guard.allowed?  # => false
  #   guard.reason    # => :auto_generated
  #
  # Every refusal names itself, so the mailbox can record *why* an email went
  # unanswered rather than silently dropping it.
  class LoopGuard
    REASONS = %i[
      bounce
      auto_generated
      mailing_list
      agent_address
      blocked_sender
      no_content
      handed_off
      reply_limit
    ].freeze

    attr_reader :inbound, :conversation

    def initialize(inbound, conversation: nil)
      @inbound = inbound
      @conversation = conversation
    end

    # @return [Symbol, nil] nil when the agent may answer
    def reason
      return :bounce if inbound.bounce?
      return :auto_generated if inbound.auto_generated?
      return :mailing_list if inbound.mailing_list?
      return :agent_address if from_agent?
      return :blocked_sender if blocked?
      return :no_content if inbound.body.blank? && inbound.attachments.empty?
      return :handed_off if handed_off?
      return :reply_limit if reply_limit_reached?

      nil
    end

    def allowed?
      reason.nil?
    end

    private

    # Mail from one of our own posting addresses: either the agent talking to
    # itself through a forwarding rule, or a reply we sent coming back.
    def from_agent?
      Addressing.match?(inbound.from, ActionMailAgent.agent_addresses)
    end

    def blocked?
      Addressing.match?(inbound.from, ActionMailAgent.blocked_senders)
    end

    # A conversation a human took over is not the agent's to answer.
    def handed_off?
      conversation.respond_to?(:handed_off?) && conversation.handed_off?
    end

    # The backstop for everything the header checks miss. Two agents talking
    # to each other produce a burst of replies on one conversation and nothing
    # else does, so the rate is the tell — not "replies since the customer
    # last wrote", which in a loop resets on every bounce of the ball.
    def reply_limit_reached?
      return false unless conversation.respond_to?(:agent_replies_within)

      conversation.agent_replies_within(ActionMailAgent.reply_rate_window) >= ActionMailAgent.reply_rate_limit
    end
  end
end
