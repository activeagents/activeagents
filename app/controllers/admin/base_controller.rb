module Admin
  class BaseController < ApplicationController
    before_action :set_account

    private

    def set_account
      @account = current_user&.primary_account
      redirect_to root_path, alert: "Account not found" unless @account
    end

    def current_user
      Current.session&.user
    end
  end
end
