class Account < ApplicationRecord
  pay_customer default_payment_processor: :stripe,
               stripe_attributes: :stripe_customer_attributes

  belongs_to :owner, class_name: "User", inverse_of: :owned_accounts
  has_many :account_memberships, dependent: :destroy
  has_many :users, through: :account_memberships

  validates :name, presence: true

  # Pay gem expects `email` and `customer_name` on the billable model.
  # Delegate email to the account owner (User) since Account doesn't have one.
  delegate :email, to: :owner

  def customer_name
    name
  end

  def stripe_customer_attributes(pay_customer)
    {
      metadata: {
        account_id: id,
        account_name: name
      }
    }
  end

  def current_plan
    active_sub = payment_processor&.subscription
    return Plan.free if active_sub.nil? || !active_sub.active?

    Plan.find_by(stripe_monthly_price_id: active_sub.processor_plan) ||
      Plan.find_by(stripe_annual_price_id: active_sub.processor_plan) ||
      Plan.free
  end

  def subscribed?
    payment_processor&.subscribed? || false
  end

  def on_trial?
    payment_processor&.on_trial? || false
  end

  def on_trial_or_subscribed?
    payment_processor&.on_trial_or_subscribed? || false
  end

  def seat_count
    account_memberships.count
  end

  def seats_remaining
    plan = current_plan
    return Float::INFINITY if plan.included_seats == -1
    plan.included_seats - seat_count
  end
end
