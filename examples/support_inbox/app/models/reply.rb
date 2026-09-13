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

  def send!
    update!(draft: false)
    ticket.waiting!
  end

  private

  def assign_message_id
    return if message_id.present?

    domain = ActionMailAgent::Addressing.domain(ticket&.support_address) || "localhost"
    self.message_id = "#{SecureRandom.uuid}@#{domain}"
  end
end
