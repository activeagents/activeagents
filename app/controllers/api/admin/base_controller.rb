module Api
  module Admin
    class BaseController < Api::BaseController
      before_action :set_account

      private

      def set_account
        @account = current_user&.primary_account
        render json: { error: "Account not found" }, status: :unauthorized unless @account
      end
    end
  end
end
