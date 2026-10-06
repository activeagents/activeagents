class WorkspaceMembersController < ApplicationController
  include ManagesWorkspaceMembers
  layout "pilot"

  def index
    @memberships = @account.account_memberships.includes(:user).order(:created_at)
    @current_membership = @memberships.find { |membership| membership.user_id == Current.user.id }
    @invitations = @account.teammate_invitations.outstanding.includes(:invited_by).order(created_at: :desc)
  end

  def update
    membership = workspace_members.change_role!(@account.account_memberships.find(params[:id]),
      params.expect(membership: [ :role ]).fetch(:role))
    redirect_to workspace_members_path, notice: "#{membership.user.email_address} is now #{membership.role == "admin" ? "an admin" : "a member"}."
  end

  def destroy
    membership = workspace_members.remove!(@account.account_memberships.find(params[:id]))
    if membership.user_id == Current.user.id
      redirect_to workspace_path, notice: "You left #{@account.name}."
    else
      redirect_to workspace_members_path, notice: "#{membership.user.email_address} was removed from #{@account.name}."
    end
  end
end
