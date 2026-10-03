# An emailed, single-use link into a workspace. It comes in two kinds:
#
# - pilot:    sent by a platform admin. The invitee becomes the owner of a
#             workspace that gets complimentary Pro. `role` is nil.
# - teammate: sent by an owner or admin of `account`. The invitee joins that
#             workspace with `role`, which the inviter chose.
#
# Only a SHA256 digest of the token is stored, and only from delivery until
# acceptance, revocation or the next resend.
class WorkspaceInvitation < ApplicationRecord
  TOKEN_LIFETIME = 7.days

  belongs_to :invited_by, class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true
  belongs_to :account, optional: true

  scope :pilot, -> { where(role: nil) }
  scope :teammate, -> { where.not(role: nil) }
  scope :outstanding, -> { where(accepted_at: nil, revoked_at: nil) }
  # A teammate invitation holds one of the workspace's seats until it is
  # accepted, revoked or expires. While its email is queued it has no expiry
  # yet, and holds the seat.
  scope :holding_seat, -> {
    teammate.outstanding.where(token_expires_at: nil).or(teammate.outstanding.where(token_expires_at: Time.current..))
  }

  normalizes :email_address, with: ->(email) { email.strip.downcase }
  validates :email_address, presence: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :workspace_name, :source, presence: true
  validates :reason, :review_on, presence: true, unless: :teammate?
  validates :workspace_name, length: { maximum: 200 }
  validates :role, inclusion: { in: AccountMembership::INVITABLE_ROLES }, allow_nil: true
  validates :account, presence: true, if: :teammate?
  validates :email_address, uniqueness: { conditions: -> { pilot.outstanding } }, if: -> { outstanding? && !teammate? }
  validates :email_address, uniqueness: { scope: :account_id, conditions: -> { teammate.outstanding },
    message: "already has a pending invitation to this workspace" }, if: -> { outstanding? && teammate? }
  validate :intended_owner, unless: :teammate?
  validate :invitee_not_a_member, if: -> { teammate? && outstanding? }
  validate :future_grant_expiration

  def self.for_token(token)
    return if !token.is_a?(String) || token.blank? || token.bytesize > 128
    find_by(token_digest: Digest::SHA256.hexdigest(token))
  end

  def teammate?
    role.present?
  end

  def outstanding?
    !accepted_at? && !revoked_at?
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

  # Whether the sender may still invite: a verified platform admin for a
  # pilot invitation, a verified owner or admin of the workspace for a
  # teammate one.
  def inviter_authorized?
    authorize!(invited_by)
    true
  rescue ProAccess::NotAuthorized, WorkspaceMembers::NotAuthorized
    false
  end

  def queue_delivery!(actor:)
    authorize!(actor)
    with_lock do
      raise ActiveRecord::RecordInvalid, self if accepted_at? || revoked_at?
      return if delivery_state == "queued"
      update!(token_digest: nil, token_expires_at: nil, delivery_state: "queued",
        delivery_error: nil, delivery_version: delivery_version + 1)
      WorkspaceInvitationDeliveryJob.perform_later(id, delivery_version)
    end
  end

  def revoke!(actor:)
    authorize!(actor)
    with_lock do
      return if revoked_at? || accepted_at?
      update!(revoked_at: Time.current, token_digest: nil)
    end
  end

  private

  def authorize!(actor)
    teammate? ? WorkspaceMembers.authorize!(account, actor) : ProAccess.authorize!(actor)
  end

  def intended_owner
    if account && account.owner.email_address != email_address
      errors.add(:account, "must be owned by the invited email address")
    end
  end

  def invitee_not_a_member
    if account&.members&.exists?(email_address: email_address)
      errors.add(:email_address, "already belongs to this workspace")
    end
  end

  def future_grant_expiration
    if grant_expires_at && !accepted_at? && grant_expires_at <= Time.current
      errors.add(:grant_expires_at, "must be in the future")
    end
  end
end
