class AccountMembership < ApplicationRecord
  ROLES = %w[owner admin member].freeze
  # Owner memberships come only from creating a workspace. Invitations and
  # role changes grant one of these.
  INVITABLE_ROLES = %w[admin member].freeze
  MANAGER_ROLES = %w[owner admin].freeze

  belongs_to :account
  belongs_to :user

  validates :role, presence: true, inclusion: { in: ROLES }
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

  # Whether this member may invite, remove and change the roles of others.
  def manages_members?
    role.in?(MANAGER_ROLES)
  end
end
