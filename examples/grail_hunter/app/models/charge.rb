# The ledger. Every fee the product takes is a row here: the per-run fee a
# discovery run cost, or a month of a subscription plan.
class Charge < ApplicationRecord
  KINDS = %w[run_fee subscription].freeze
  STATUSES = %w[pending settled voided].freeze

  belongs_to :user
  belongs_to :discovery_run, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :description, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :settled, -> { where(status: "settled") }
  scope :this_month, -> { where(created_at: Time.current.all_month) }

  def run_fee?
    kind == "run_fee"
  end

  def subscription?
    kind == "subscription"
  end
end
