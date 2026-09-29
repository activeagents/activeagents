module Admin
  class PilotsController < BaseController
    layout "pilot"
    before_action :require_verified_user!

    def index
      @invitations = WorkspaceInvitation.includes(:account, :invited_by).order(created_at: :desc).limit(100)
      @accounts = Account.includes(:owner, :pro_access_grant).order(id: :desc).limit(100)
      @events = ProAccessEvent.includes(:actor, pro_access_grant: :account).order(id: :desc).limit(50)
    end
  end
end
