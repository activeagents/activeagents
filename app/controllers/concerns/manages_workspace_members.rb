# Shared by the controllers that change who belongs to the current workspace.
module ManagesWorkspaceMembers
  extend ActiveSupport::Concern

  included do
    before_action :require_verified_user!
    before_action :set_account

    rescue_from WorkspaceMembers::NotAuthorized do
      redirect_to workspace_members_path, alert: "Only the workspace's owners and admins can manage members."
    end
    rescue_from WorkspaceMembers::Refused do |error|
      redirect_to workspace_members_path, alert: error.message
    end
  end

  private

  def set_account
    @account = Current.account
    redirect_to plans_path, alert: "Choose a plan to set up a workspace." unless @account
  end

  def workspace_members
    WorkspaceMembers.new(@account, actor: Current.user)
  end
end
