class ProAccessExpirationJob < ApplicationJob
  def perform
    ProAccessGrant.where(revoked_at: nil, expiration_recorded_at: nil)
      .where("expires_at <= ?", Time.current).find_each { |grant| ProAccess.expire!(grant) }
  end
end
