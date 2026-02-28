class Investor < ApplicationRecord
  belongs_to :account
  belongs_to :user, optional: true

  has_many :safe_agreements, dependent: :destroy
  has_many :cap_table_entries, dependent: :nullify
  has_many :document_access_grants, dependent: :destroy
  has_many :accessible_documents, through: :document_access_grants, source: :investor_document
  has_many :document_access_logs, dependent: :destroy

  validates :email, presence: true, uniqueness: { scope: :account_id }
  validates :name, presence: true
  validates :investor_type, inclusion: { in: %w[individual entity trust] }

  normalizes :email, with: ->(e) { e.strip.downcase }

  before_create :generate_access_token

  scope :with_portal_access, -> { where(portal_enabled: true) }
  scope :active, -> { where(portal_enabled: true) }

  def generate_access_token!
    update!(
      access_token: SecureRandom.urlsafe_base64(32),
      access_token_expires_at: 30.days.from_now
    )
  end

  def access_token_valid?
    access_token.present? && access_token_expires_at&.future?
  end

  def total_invested
    safe_agreements.where(status: %w[signed converted]).sum(:investment_amount)
  end

  def ownership_summary
    cap_table_entries.sum(:ownership_percent)
  end

  def display_name
    legal_name.presence || name
  end

  private

  def generate_access_token
    self.access_token ||= SecureRandom.urlsafe_base64(32)
    self.access_token_expires_at ||= 30.days.from_now
  end
end
