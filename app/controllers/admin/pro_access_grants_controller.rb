module Admin
  class ProAccessGrantsController < BaseController
    before_action :require_verified_user!

    def create
      account = Account.find(params[:account_id])
      ProAccess.grant!(account: account, actor: Current.user, **grant_params.to_h.symbolize_keys)
      redirect_to admin_pilots_path, notice: "Pro access saved. The owner will receive a transactional notice."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to admin_pilots_path, alert: error.record.errors.full_messages.to_sentence
    end

    def destroy
      ProAccess.revoke!(grant: ProAccessGrant.find(params[:id]), actor: Current.user)
      redirect_to admin_pilots_path, notice: "Complimentary access revoked. Paid subscriptions are unchanged."
    end

    private

    def grant_params
      params.require(:grant).permit(:source, :reason, :starts_at, :review_on, :expires_at)
    end
  end
end
