class TeammateInvitationsController < ApplicationController
  include ManagesWorkspaceMembers
  # Each send emails someone outside the workspace.
  rate_limit to: 20, within: 1.hour, by: -> { @account.id }, only: %i[create resend],
    with: -> { redirect_to workspace_members_path, alert: "This workspace has sent too many invitations. Try again in an hour." }

  def create
    attributes = params.expect(invitation: [ :email_address, :role ])
    invitation = workspace_members.invite!(email_address: attributes[:email_address], role: attributes[:role])
    redirect_to workspace_members_path, notice: "Invitation sent to #{invitation.email_address}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_members_path, alert: error.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    redirect_to workspace_members_path, alert: "That email already has a pending invitation to this workspace."
  end

  def resend
    workspace_members.resend!(invitation)
    redirect_to workspace_members_path, notice: "Invitation resent to #{invitation.email_address}. The previous link no longer works."
  rescue ActiveRecord::RecordInvalid
    redirect_to workspace_members_path, alert: "Accepted or revoked invitations can't be resent."
  end

  def destroy
    workspace_members.revoke!(invitation)
    redirect_to workspace_members_path, notice: "The invitation to #{invitation.email_address} was revoked."
  end

  private

  def invitation
    @invitation ||= @account.teammate_invitations.find(params[:id])
  end
end
