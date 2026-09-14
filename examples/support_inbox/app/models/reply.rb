class Reply < ApplicationRecord
  belongs_to :ticket

  validates :body, :author, presence: true

  scope :drafts, -> { where(draft: true) }
  scope :sent, -> { where(draft: false) }
  scope :inbound, -> { where(inbound: true) }
  scope :outbound, -> { where(inbound: false) }

  # An outbound reply gets its Message-Id before it is sent, not after: the
  # id has to be on record for the customer's answer — which will carry it in
  # In-Reply-To — to find its way back to this ticket, and a reply that is
  # generated now and delivered later (draft mode, a queued mailer) would
  # otherwise have no id at all in between.
  before_create :assign_message_id, unless: :inbound?

  def delivered?
    delivered_at.present?
  end

  # Sends this reply: on an email ticket that means emailing the customer,
  # threaded onto their conversation. The same path whether the agent's
  # answer is delivered straight away by SupportMailbox or a person clicks
  # "Send this draft" in the inbox — one door out, so a reply cannot be
  # marked sent without having been sent.
  def send!
    deliver_by_email! if ticket.email? && !inbound?
    update!(draft: false)
    ticket.waiting!
  end

  def deliver_by_email!
    SupportMailer.with(ticket: ticket, reply: self).answer.deliver_now
    update!(delivered_at: Time.current)
  end

  private

  def assign_message_id
    return if message_id.present?

    domain = ActionMailAgent::Addressing.domain(ticket&.support_address) || "localhost"
    self.message_id = "#{SecureRandom.uuid}@#{domain}"
  end
end
