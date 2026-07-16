# frozen_string_literal: true

module Api
  class BaseController < ApplicationController
    skip_before_action :verify_authenticity_token

    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
    rescue_from ActionController::ParameterMissing, with: :bad_request

    private

    def current_user
      Current.session&.user
    end

    def current_account
      @current_account ||= current_user&.primary_account
    end

    def require_account!
      render json: { error: "No account" }, status: :unauthorized if current_account.nil?
    end

    def not_found
      render json: { error: "Record not found" }, status: :not_found
    end

    def unprocessable_entity(exception)
      render json: { error: exception.record.errors.full_messages }, status: :unprocessable_entity
    end

    def bad_request(exception)
      render json: { error: exception.message }, status: :bad_request
    end
  end
end
