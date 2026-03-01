class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :agents, dependent: :destroy

  has_many :account_memberships, dependent: :destroy
  has_many :accounts, through: :account_memberships
  has_many :owned_accounts, class_name: "Account", foreign_key: :owner_id, dependent: :destroy, inverse_of: :owner

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, if: -> { new_record? || password.present? }

  def display_name
    email_address.split("@").first.titleize
  end

  def primary_account
    owned_accounts.first || accounts.first
  end

  def admin?
    admin == true
  end
end
