class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :hunts, dependent: :destroy
  has_many :discovery_runs, dependent: :destroy
  has_many :findings, dependent: :destroy
  has_many :charges, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :plan_key, inclusion: { in: ->(_) { Plan.keys } }

  # The first account on an install is its admin. The dashboard at
  # /activeagents shows every hunt's prompts and tool calls, so it is for the
  # operator, not for customers.
  before_create { self.admin = true if User.none? }

  def plan
    Plan.find(plan_key)
  end

  def subscribed?
    plan.subscription?
  end

  def display_name
    name.presence || email_address
  end

  # Everything the product has charged this calendar month.
  def month_to_date_cents
    charges.settled.this_month.sum(:amount_cents)
  end

  def active_hunt_cap_reached?
    hunts.active.count >= plan.max_active_hunts
  end
end
