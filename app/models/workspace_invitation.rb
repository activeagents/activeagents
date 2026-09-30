class WorkspaceInvitation < ApplicationRecord
  TOKEN_LIFETIME = 7.days

  belongs_to :invited_by, class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true
  belongs_to :account, optional: true
  normalizes :email_address, with: ->(email) { email.strip.downcase }
  validates :email_address, presence: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :workspace_name, :reason, :source, :review_on, presence: true
  validates :workspace_name, length: { maximum: 200 }
  validates :email_address, uniqueness: { conditions: -> { where(accepted_at: nil, revoked_at: nil) } }, if: -> { !accepted_at? && !revoked_at? }
  validate :intended_owner
  validate :future_grant_expiration

  def self.for_token(token)
    return if !token.is_a?(String) || token.blank? || token.bytesize > 128
    find_by(token_digest: Digest::SHA256.hexdigest(token))
  end

  def usable?
    !accepted_at? && !revoked_at? && token_digest? && token_expires_at && token_expires_at > Time.current
  end

  def status
    return "accepted" if accepted_at?
    return "revoked" if revoked_at?
    return "expired" if token_expires_at && token_expires_at <= Time.current
    delivery_state == "sent" ? "pending" : delivery_state
  end

  def queue_delivery!(actor:)
    ProAccess.authorize!(actor)
    with_lock do
      raise ActiveRecord::RecordInvalid, self if accepted_at? || revoked_at?
      return if delivery_state == "queued"
      update!(token_digest: nil, token_expires_at: nil, delivery_state: "queued",
        delivery_error: nil, delivery_version: delivery_version + 1)
      WorkspaceInvitationDeliveryJob.perform_later(id, delivery_version)
    end
  end

  def revoke!(actor:)
    ProAccess.authorize!(actor)
    with_lock do
      return if revoked_at? || accepted_at?
      update!(revoked_at: Time.current, token_digest: nil)
    end
  end

  private

  def intended_owner
    if account && account.owner.email_address != email_address
      errors.add(:account, "must be owned by the invited email address")
    end
  end

  def future_grant_expiration
    if grant_expires_at && !accepted_at? && grant_expires_at <= Time.current
      errors.add(:grant_expires_at, "must be in the future")
    end
  end
end
