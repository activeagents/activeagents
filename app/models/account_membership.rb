class AccountMembership < ApplicationRecord
  belongs_to :account
  belongs_to :user

  validates :role, presence: true, inclusion: { in: %w[owner admin member] }
  validates :user_id, uniqueness: { scope: :account_id }

  def owner?
    role == "owner"
  end

  def admin?
    role == "admin"
  end

  def member?
    role == "member"
  end
end
