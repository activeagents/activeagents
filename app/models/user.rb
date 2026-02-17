class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :agents, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, if: -> { new_record? || password.present? }

  def display_name
    email_address.split("@").first.titleize
  end
end
