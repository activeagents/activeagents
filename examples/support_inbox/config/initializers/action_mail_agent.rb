# frozen_string_literal: true

# Email transport for the support agent (see lib/action_mail_agent).
#
# Wrapped in to_prepare because ActionMailAgent is autoloaded from lib/: a
# plain initializer would configure a copy of the module that gets thrown away
# on the first reload in development.
Rails.application.config.to_prepare do
  ActionMailAgent.configure do |config|
    # The inbox. Replies come back to support+<ticket token>@ — see
    # ApplicationMailbox for the routes that accept both.
    config.default_from = ENV.fetch("SUPPORT_ADDRESS", "support@example.com")

    # :auto sends the agent's answer, :draft records it for a human to read
    # and sends nothing, :off stops generating entirely. Rolling an agent out
    # in front of real customers starts at :draft.
    config.delivery_mode = ENV.fetch("SUPPORT_DELIVERY_MODE", "auto").to_sym

    # Mail from our own addresses is never answered — that is what a loop
    # looks like from the inside.
    config.agent_addresses = [ config.default_from, /\Asupport\+/ ]

    # More than three answers on one ticket in ten minutes is not a
    # conversation; the ticket goes to a human instead.
    config.reply_rate_limit = 3
    config.reply_rate_window = 10.minutes

    # Rendered at the top of every outgoing reply, and recognised as a quote
    # boundary when it comes back inside the customer's quoted thread.
    config.reply_delimiter = "##- Please type your reply above this line -##"

    # What a handoff means here: a line in the log. A real deployment pages
    # the on-call support engineer, or assigns the ticket in whatever the
    # team already uses.
    config.handoff_notifier = lambda do |ticket, reason|
      Rails.logger.warn("[support] ticket ##{ticket.id} handed to a human: #{reason}")
    end
  end
end
