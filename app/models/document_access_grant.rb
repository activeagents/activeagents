class DocumentAccessGrant < ApplicationRecord
  belongs_to :investor_document
  belongs_to :investor

  validates :granted_at, presence: true
  validates :investor_id, uniqueness: { scope: :investor_document_id }

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }
  scope :revoked, -> { where.not(revoked_at: nil) }

  def revoke!
    update!(revoked_at: Time.current)
  end

  def active?
    revoked_at.nil? && (expires_at.nil? || expires_at.future?)
  end

  def expired?
    expires_at.present? && expires_at.past?
  end
end
