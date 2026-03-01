# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    before_action :require_admin!

    private

    def require_admin!
      unless current_user&.admin?
        redirect_to root_path, alert: "Access denied"
      end
    end

    def current_user
      Current.session&.user
    end
  end
end
