class InvestorDocument < ApplicationRecord
  DOCUMENT_TYPES = %w[ppm pitch_deck safe side_letter cap_table other].freeze

  belongs_to :account
  belongs_to :safe_agreement, optional: true

  has_one_attached :file

  has_many :document_access_grants, dependent: :destroy
  has_many :authorized_investors, through: :document_access_grants, source: :investor
  has_many :document_access_logs, dependent: :destroy

  validates :name, presence: true
  validates :document_type, presence: true, inclusion: { in: DOCUMENT_TYPES }
  validates :file, presence: true, on: :create

  scope :by_type, ->(type) { where(document_type: type) }
  scope :public_documents, -> { where(public_to_all_investors: true) }

  def accessible_by?(investor)
    return true if public_to_all_investors
    document_access_grants.active.exists?(investor: investor)
  end

  def grant_access_to(investor, expires_at: nil)
    document_access_grants.find_or_create_by!(investor: investor) do |grant|
      grant.granted_at = Time.current
      grant.expires_at = expires_at
    end
  end

  def revoke_access_from(investor)
    document_access_grants.find_by(investor: investor)&.revoke!
  end

  def log_access(investor, action:, ip_address: nil, user_agent: nil)
    document_access_logs.create!(
      investor: investor,
      action: action,
      ip_address: ip_address,
      user_agent: user_agent
    )
  end

  def view_count
    document_access_logs.views.count
  end

  def download_count
    document_access_logs.downloads.count
  end

  def unique_viewers_count
    document_access_logs.select(:investor_id).distinct.count
  end

  def document_type_label
    case document_type
    when "ppm" then "Private Placement Memorandum"
    when "pitch_deck" then "Pitch Deck"
    when "safe" then "SAFE Agreement"
    when "side_letter" then "Side Letter"
    when "cap_table" then "Cap Table"
    else "Other Document"
    end
  end
end
