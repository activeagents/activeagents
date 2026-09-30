class ProAccessGrant < ApplicationRecord
  belongs_to :account
  belongs_to :granted_by, class_name: "User"
  has_many :events, class_name: "ProAccessEvent", dependent: :destroy

  validates :source, :reason, :starts_at, :review_on, presence: true
  validates :account_id, uniqueness: true
  validates :source, length: { maximum: 80 }
  validate :expiration_after_start

  def active?(at: Time.current)
    revoked_at.nil? && starts_at <= at && (expires_at.nil? || expires_at > at)
  end

  def ended_at
    [ revoked_at, expires_at ].compact.min
  end

  # Keep the Pro retention window for 14 days after access ends. Existing
  # traces age out normally; losing a grant never triggers an immediate purge.
  def retention_grace?
    ended_at.present? && Time.current.between?(ended_at, ended_at + 14.days)
  end

  private

  def expiration_after_start
    if expires_at && starts_at && expires_at <= starts_at
      errors.add(:expires_at, "must be after the start date")
    end
  end
end
