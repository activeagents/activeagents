class Plan < ApplicationRecord
  scope :active, -> { where(active: true) }
  scope :paid, -> { where("price_cents > 0") }
  scope :free, -> { where(price_cents: 0) }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  def free?
    price_cents.zero?
  end

  def price_dollars
    price_cents / 100.0
  end

  def annual_price_dollars
    annual_price_cents / 100.0
  end

  def feature?(key)
    features&.dig(key.to_s) == true
  end
end
