class SafeAgreement < ApplicationRecord
  belongs_to :account
  belongs_to :investor

  has_many :investor_documents, dependent: :nullify
  has_one :cap_table_entry, dependent: :nullify

  validates :investment_amount, presence: true, numericality: { greater_than: 0 }
  validates :safe_type, inclusion: { in: %w[pre_money post_money mfn] }
  validates :status, inclusion: { in: %w[draft sent signed converted cancelled] }

  scope :pending, -> { where(status: %w[draft sent]) }
  scope :active, -> { where(status: %w[sent signed]) }
  scope :signed, -> { where(status: "signed") }
  scope :converted, -> { where(status: "converted") }

  def mark_as_sent!
    update!(status: "sent", sent_at: Time.current)
  end

  def mark_as_signed!
    update!(status: "signed", signed_at: Time.current)
  end

  def cancel!
    update!(status: "cancelled", cancelled_at: Time.current)
  end

  def convert!(shares:, price_per_share:, round_name:)
    transaction do
      update!(
        status: "converted",
        converted_at: Time.current,
        conversion_shares: shares,
        conversion_price_per_share: price_per_share,
        conversion_round_name: round_name
      )

      # Create cap table entry for the converted shares
      CapTableEntry.create!(
        account: account,
        investor: investor,
        safe_agreement: self,
        stakeholder_name: investor.display_name,
        stakeholder_type: "investor",
        security_type: "preferred",
        security_class: round_name,
        shares: shares
      )
    end
  end

  def display_status
    case status
    when "draft" then "Draft"
    when "sent" then "Pending Signature"
    when "signed" then "Signed"
    when "converted" then "Converted"
    when "cancelled" then "Cancelled"
    end
  end

  def investment_amount_dollars
    investment_amount.to_f
  end

  def valuation_cap_dollars
    valuation_cap&.to_f
  end
end
