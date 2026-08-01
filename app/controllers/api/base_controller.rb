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

    # Standard JSON shape for an Active Storage attachment (agent exports,
    # run-context exports): metadata plus a same-host download path. The
    # blob URL is a capability link, so it is minted with a short expiry
    # (mirrors RecordingSnapshot#signed_url) — refetching the parent
    # resource re-mints it.
    ATTACHMENT_URL_TTL = 15.minutes

    def attachment_json(attachment)
      return nil unless attachment.attached?

      blob = attachment.blob
      {
        filename: blob.filename.to_s,
        content_type: blob.content_type,
        byte_size: blob.byte_size,
        url: Rails.application.routes.url_helpers.rails_service_blob_path(
          blob.signed_id(expires_in: ATTACHMENT_URL_TTL), blob.filename, disposition: "attachment"
        ),
        expires_in_seconds: ATTACHMENT_URL_TTL.to_i,
        attached_at: blob.created_at.iso8601
      }
    end

    def unprocessable_entity(exception)
      render json: { error: exception.record.errors.full_messages }, status: :unprocessable_entity
    end

    def bad_request(exception)
      render json: { error: exception.message }, status: :bad_request
    end
  end
end
