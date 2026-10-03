class User < ApplicationRecord
  has_secure_password
  generates_token_for :password_reset, expires_in: 15.minutes

  has_many :sessions, dependent: :destroy
  has_many :identities, class_name: "UserIdentity", dependent: :destroy
  has_one :github_identity, -> { where(provider: "github") }, class_name: "UserIdentity", inverse_of: :user
  # Lives in the dashboard engine now, so the association names it explicitly:
  # Rails resolves a bare :agents to a class literally named Agent, and the
  # app-level constant is an alias rather than a class of its own.
  has_many :agents, class_name: "ActionAgent::Agent", dependent: :destroy

  has_many :account_memberships, dependent: :destroy
  has_many :accounts, through: :account_memberships
  has_many :owned_accounts, class_name: "Account", foreign_key: :owner_id, dependent: :destroy, inverse_of: :owner

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, if: -> { new_record? || password.present? }

  # Email verification. The token signs its holder in, so a user whose email
  # is already verified gets none.
  before_create :generate_email_verification_token, unless: :email_verified?

  # Marks the password as one the person chose, so an account created through
  # GitHub knows when it gains a second way to sign in.
  def password=(value)
    super
    self.password_set = true if password_digest_changed?
  end

  # Gives the user a random password nobody knows, for an account that signs
  # in another way until the person chooses one.
  def assign_random_password
    self.password = SecureRandom.base58(32)
    self.password_set = false
  end

  # Saves the user together with the workspace they own, as every signup does.
  # Returns false, saving nothing, when the user is invalid.
  def save_with_workspace
    transaction do
      return false unless save
      account = Account.create!(name: "#{display_name}'s Workspace", owner: self)
      AccountMembership.create!(account: account, user: self, role: "owner")
    end
    true
  end

  def display_name
    if first_name.present? || last_name.present?
      [ first_name, last_name ].compact.join(" ")
    else
      email_address.split("@").first.titleize
    end
  end

  def primary_account
    owned_accounts.first || accounts.first
  end

  def accessible_accounts
    Account.where(owner_id: id).or(Account.where(id: accounts.select(:id)))
  end

  def admin?
    admin == true
  end

  # Email verification methods
  def generate_email_verification_token
    self.email_verification_token = SecureRandom.urlsafe_base64(32)
  end

  def send_verification_email!
    generate_email_verification_token if email_verification_token.blank?
    update!(email_verification_sent_at: Time.current)
    UserMailer.email_verification(self).deliver_later
  end

  def verify_email!(token)
    return false unless token.present? && email_verification_token == token

    update!(
      email_verified: true,
      email_verification_token: nil
    )

    # Broadcast to pending_verification page to trigger redirect
    broadcast_email_verified

    true
  end

  def broadcast_email_verified
    ActionCable.server.broadcast(
      "email_verification_#{id}",
      { type: "email_verified", redirect_to: "/complete_profile" }
    )
  end

  def email_verified?
    email_verified == true
  end

  def profile_completed?
    profile_completed == true
  end

  def needs_profile_completion?
    email_verified? && !profile_completed?
  end

  def complete_profile!(attrs)
    update_attrs = {
      first_name: attrs[:first_name],
      last_name: attrs[:last_name],
      company_name: attrs[:company_name],
      job_title: attrs[:job_title],
      profile_completed: true
    }

    # Update password if provided (for users who signed up with email-only flow)
    if attrs[:password].present?
      update_attrs[:password] = attrs[:password]
      update_attrs[:password_confirmation] = attrs[:password_confirmation]
    end

    update!(update_attrs)
  end

  def onboarding_step
    return :verify_email unless email_verified?
    return :complete_profile unless profile_completed?
    :complete
  end
end
