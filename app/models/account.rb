class Account < ApplicationRecord
  pay_customer stripe_attributes: :stripe_attributes

  belongs_to :owner, class_name: "User", inverse_of: :owned_accounts
  delegate :email_address, to: :owner
  alias_method :email, :email_address
  has_many :account_memberships, dependent: :destroy
  has_many :members, through: :account_memberships, source: :user

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

  # Telemetry methods

  # Has many telemetry traces received from ActiveAgent clients
  has_many :telemetry_traces, dependent: :destroy

  # Generates a new telemetry API key for this account
  def generate_telemetry_api_key!
    update!(telemetry_api_key: SecureRandom.hex(32))
    telemetry_api_key
  end

  # Regenerates the telemetry API key (invalidates old one)
  def regenerate_telemetry_api_key!
    generate_telemetry_api_key!
  end

  # Increments telemetry usage counter (for rate limiting/billing)
  def increment_telemetry_usage!
    # No-op for now, can add rate limiting later
  end
end
