class WorkspaceInvitationDeliveryJob < ApplicationJob
  self.enqueue_after_transaction_commit = true
  # Tokens are created inside the job, never serialized in its arguments/logs.
  # Deliberately no automatic SMTP retries: delivery can be ambiguous. An admin
  # explicitly resends, rotating the token and the delivery version.
  def perform(invitation_id, version)
    invitation = WorkspaceInvitation.find(invitation_id)
    invitation.with_lock do
      return unless invitation.delivery_version == version && invitation.delivery_state == "queued"
      return if invitation.accepted_at? || invitation.revoked_at?

      token = SecureRandom.urlsafe_base64(32)
      invitation.update!(token_digest: Digest::SHA256.hexdigest(token), token_expires_at: WorkspaceInvitation::TOKEN_LIFETIME.from_now)
      begin
        PilotMailer.invitation(invitation, token).deliver_now
        invitation.update!(delivery_state: "sent", sent_at: Time.current)
      rescue StandardError => error
        invitation.update!(delivery_state: "delivery_failed", delivery_error: error.class.name, token_digest: nil)
        Rails.logger.warn("Pilot invitation #{invitation.id} delivery failed (#{error.class.name})")
      end
    end
  end
end
