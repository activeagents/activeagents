class AcceptWorkspaceInvitation
  class Invalid < StandardError; end
  class SignInRequired < StandardError; end

  def self.call(token:, signed_in_user:, password: nil, password_confirmation: nil)
    invitation = WorkspaceInvitation.for_token(token)
    raise Invalid, "This invitation is invalid or no longer available." unless invitation

    invitation.with_lock do
      # Check again after locking: another acceptance/resend may have won.
      unless invitation.usable? && invitation.token_digest == Digest::SHA256.hexdigest(token)
        raise Invalid, "This invitation is invalid or no longer available."
      end
      ProAccess.authorize!(invitation.invited_by)
      user = User.find_by(email_address: invitation.email_address)
      if signed_in_user && signed_in_user.email_address != invitation.email_address
        raise SignInRequired, "Sign in with the invited email address to accept."
      end
      if user && signed_in_user&.id != user.id
        raise SignInRequired, "Sign in with the invited email address to accept."
      end
      user ||= User.create!(email_address: invitation.email_address, password: password,
        password_confirmation: password_confirmation, email_verified: true,
        profile_completed: true, signup_source: "retainer_pilot")
      user.with_lock do
        user.update!(email_verified: true, email_verification_token: nil)
        account = invitation.account || user.owned_accounts.create!(name: invitation.workspace_name)
        raise Invalid, "The workspace owner has changed." unless account.owner_id == user.id
        account.account_memberships.find_or_initialize_by(user: user).update!(role: "owner")
        ProAccess.grant!(account: account, actor: invitation.invited_by, source: invitation.source,
          reason: invitation.reason, starts_at: Time.current, review_on: invitation.review_on, expires_at: invitation.grant_expires_at)
        invitation.update!(account: account, accepted_by: user, accepted_at: Time.current, token_digest: nil)
      end
      invitation
    end
  rescue ActiveRecord::RecordNotUnique
    # A simultaneous public registration must authenticate before accepting.
    raise SignInRequired, "This email is now registered. Sign in to accept your invitation."
  end
end
