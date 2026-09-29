class WorkspacesController < ApplicationController
  before_action :require_verified_user!
  layout "pilot"

  def show
    @account = Current.account
    @accounts = Current.user.accessible_accounts.order(:name)
    redirect_to plans_path, alert: "Choose a plan to set up a workspace." unless @account
  end

  def update
    account = Current.user.accessible_accounts.find(params[:account_id])
    Current.session.update!(account: account)
    redirect_to workspace_path
  end
end
