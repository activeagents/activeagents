module Admin
  class PilotInvitationsController < BaseController
    before_action :require_verified_user!

    def create
      ProAccess.authorize!(Current.user)
      invitation = WorkspaceInvitation.new(invitation_params.merge(invited_by: Current.user))
      if (account_id = params.require(:invitation)[:account_id]).present?
        invitation.account = Account.find(account_id)
      end
      invitation.save!
      redirect_to admin_pilots_path, notice: "Invitation prepared. Review the recipient, then send explicitly."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to admin_pilots_path, alert: error.record.errors.full_messages.to_sentence
    rescue ActiveRecord::RecordNotUnique
      redirect_to admin_pilots_path, alert: "A pending invitation already exists for this email. Resend or revoke it first."
    end

    def deliver
      WorkspaceInvitation.find(params[:id]).queue_delivery!(actor: Current.user)
      redirect_to admin_pilots_path, notice: "Invitation delivery queued. Previous links are no longer valid."
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_pilots_path, alert: "Accepted or revoked invitations cannot be resent."
    end

    def revoke
      WorkspaceInvitation.find(params[:id]).revoke!(actor: Current.user)
      redirect_to admin_pilots_path, notice: "Invitation revoked. Accepted workspace access is managed separately."
    end

    private

    def invitation_params
      params.require(:invitation).permit(:email_address, :workspace_name, :reason, :review_on, :grant_expires_at)
    end
  end
end
