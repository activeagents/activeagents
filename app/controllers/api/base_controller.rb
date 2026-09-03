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

    # Reads an integer from params, falling back to `default` when the value
    # is absent or blank. Non-numeric input becomes 0 via to_i.
    #
    # A param can arrive as a container rather than a scalar (`page[]=1&page[]=2`
    # from a query string, or a JSON object in the body). Array and
    # ActionController::Parameters do not respond to `to_i`, so reading them
    # directly raised NoMethodError and returned a 500 where a default or a
    # clamped value was intended. A multi-valued param means its first value
    # (Array#to_s would concatenate them, turning [1, 2] into 12); a nested
    # object is malformed and becomes 0 like any other non-numeric input.
    def integer_param(name, default: nil)
      raw = params[name]
      raw = raw.first if raw.is_a?(Array)
      return default if raw.blank?

      raw.to_s.to_i
    end

    # integer_param, then clamped into [min, max]. Non-numeric input becomes
    # 0 and is then clamped up to `min`.
    def clamped_param(name, default:, min:, max:)
      integer_param(name, default: default).clamp(min, max)
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
