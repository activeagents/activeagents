class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true

  def account
    return unless user
    return user.primary_account unless session.account_id
    # Recheck membership on every request; a stale session is not authority.
    user.accessible_accounts.find_by(id: session.account_id)
  end
end
