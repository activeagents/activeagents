class User < ApplicationRecord
  has_secure_password

  has_many :account_memberships, dependent: :destroy
  has_many :accounts, through: :account_memberships
  has_many :owned_accounts, class_name: "Account", foreign_key: :owner_id, dependent: :destroy, inverse_of: :owner

  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  normalizes :email, with: ->(email) { email.strip.downcase }

  def default_account
    owned_accounts.first || accounts.first
  end
end
