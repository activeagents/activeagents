class CapTableEntry < ApplicationRecord
  STAKEHOLDER_TYPES = %w[founder investor employee advisor].freeze
  SECURITY_TYPES = %w[common preferred safe option warrant].freeze

  belongs_to :account
  belongs_to :investor, optional: true
  belongs_to :safe_agreement, optional: true

  validates :stakeholder_name, presence: true
  validates :stakeholder_type, inclusion: { in: STAKEHOLDER_TYPES }
  validates :security_type, inclusion: { in: SECURITY_TYPES }

  scope :by_stakeholder_type, ->(type) { where(stakeholder_type: type) }
  scope :by_security_type, ->(type) { where(security_type: type) }
  scope :equity, -> { where(security_type: %w[common preferred]) }
  scope :convertibles, -> { where(security_type: "safe") }
  scope :options, -> { where(security_type: %w[option warrant]) }
  scope :founders, -> { where(stakeholder_type: "founder") }
  scope :investors, -> { where(stakeholder_type: "investor") }

  def vested_percent
    return 100.0 if vested_shares.nil? || shares.nil? || shares.zero?
    (vested_shares.to_f / shares.to_f * 100).round(2)
  end

  def unvested_shares
    return 0 if vested_shares.nil? || shares.nil?
    shares - vested_shares
  end

  def security_label
    label = security_type.titleize
    label += " (#{security_class})" if security_class.present?
    label
  end

  def stakeholder_type_label
    stakeholder_type.titleize
  end
end
