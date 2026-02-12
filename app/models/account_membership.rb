class AccountMembership < ApplicationRecord
  belongs_to :account
  belongs_to :user

  validates :user_id, uniqueness: { scope: :account_id, message: "is already a member of this account" }
  validates :role, presence: true, inclusion: { in: %w[owner admin member] }
end
