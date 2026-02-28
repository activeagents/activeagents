class Account < ApplicationRecord
  pay_customer stripe_attributes: :stripe_attributes

  belongs_to :owner, class_name: "User", inverse_of: :owned_accounts
  delegate :email_address, to: :owner
  alias_method :email, :email_address
  has_many :account_memberships, dependent: :destroy
  has_many :members, through: :account_memberships, source: :user

  # Investor portal associations
  has_many :investors, dependent: :destroy
  has_many :safe_agreements, dependent: :destroy
  has_many :investor_documents, dependent: :destroy
  has_many :cap_table_entries, dependent: :destroy

  validates :name, presence: true

  def stripe_attributes(pay_customer)
    {
      metadata: {
        account_id: id,
        account_name: name
      }
    }
  end

  def active_subscription
    pay_customers.flat_map(&:subscriptions).find(&:active?)
  end

  def subscribed?
    active_subscription.present?
  end

  def current_plan
    if active_subscription
      stripe_price_id = active_subscription.processor_plan
      Plan.find_by(stripe_monthly_price_id: stripe_price_id) ||
        Plan.find_by(stripe_annual_price_id: stripe_price_id)
    else
      # Default to free plan for users without a subscription
      Plan.free.first
    end
  end

  # Investor portal helpers
  def total_raised
    safe_agreements.signed.sum(:investment_amount) + safe_agreements.converted.sum(:investment_amount)
  end

  def pending_safes_amount
    safe_agreements.pending.sum(:investment_amount)
  end

  def investor_count
    investors.count
  end
end
