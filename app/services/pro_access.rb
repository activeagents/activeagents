# All mutations lock the workspace, including calls inside invite acceptance.
# There is one grant per workspace; the immutable events retain its history.
class ProAccess
  class NotAuthorized < StandardError; end

  def self.authorize!(actor)
    raise NotAuthorized unless actor&.admin? && actor.email_verified?
  end

  def self.grant!(account:, actor:, source:, reason:, review_on:, starts_at: nil, expires_at: nil)
    authorize!(actor)
    Plan.find_by!(slug: "pro")
    account.with_lock do
      grant = ProAccessGrant.find_or_initialize_by(account: account)
      action = grant.new_record? || grant.revoked_at? ? "granted" : "updated"
      grant.assign_attributes(source: source, reason: reason, review_on: review_on,
        starts_at: starts_at.presence || grant.starts_at || Time.current, expires_at: expires_at, revoked_at: nil)
      return grant unless grant.changed?

      grant.granted_by = actor
      grant.expiration_recorded_at = nil
      grant.save!
      record!(grant, action, actor)
      account.association(:pro_access_grant).reset
      grant
    end
  end

  def self.revoke!(grant:, actor:)
    authorize!(actor)
    grant.account.with_lock do
      grant.reload
      return grant if grant.revoked_at?

      grant.update!(revoked_at: Time.current)
      record!(grant, "revoked", actor)
      grant.account.association(:pro_access_grant).reset
      grant
    end
  end

  def self.expire!(grant)
    grant.account.with_lock do
      grant.reload
      return if grant.revoked_at? || grant.expiration_recorded_at? || !grant.expires_at || grant.expires_at > Time.current

      grant.update!(expiration_recorded_at: Time.current)
      record!(grant, "expired", nil)
    end
  end

  def self.record!(grant, action, actor)
    grant.events.create!(action: action, actor: actor,
      details: grant.attributes.slice("source", "reason", "starts_at", "review_on", "expires_at", "revoked_at"))
  end
  private_class_method :record!
end
