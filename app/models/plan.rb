class Plan < ApplicationRecord
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :paid, -> { where.not(slug: "free") }

  def self.free
    find_by(slug: "free")
  end

  def self.pro
    find_by(slug: "pro")
  end

  def self.enterprise
    find_by(slug: "enterprise")
  end

  def free?
    slug == "free"
  end

  def requires_payment?
    !free?
  end

  def annual_savings_percent
    return 0 if annual_price_cents.zero? || price_cents.zero?
    monthly_cost = price_cents * 12
    ((monthly_cost - annual_price_cents).to_f / monthly_cost * 100).round(0)
  end
end
