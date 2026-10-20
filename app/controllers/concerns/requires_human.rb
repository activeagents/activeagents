# frozen_string_literal: true

# Refuses a public form submission that fails HumanCheck (filled honeypot, or a
# missing or invalid Turnstile token) before the action runs.
#
#   class RegistrationsController < ApplicationController
#     include RequiresHuman
#     require_human only: :create
#   end
#
# The refusal is a 422 with the same shape the actions use for their own
# errors: JSON `{ error: ... }` for JSON requests, otherwise a redirect back to
# the form carrying the message in the flash. A controller can override
# +human_check_failed+ to render differently.
module RequiresHuman
  extend ActiveSupport::Concern

  MESSAGE = "We couldn't confirm you're a person. Please try again."

  class_methods do
    def require_human(**options)
      before_action :require_human!, **options
    end
  end

  private

  def require_human!
    result = HumanCheck.check(params, remote_ip: request.remote_ip)
    return if result.ok?

    Rails.logger.info("HumanCheck refused #{request.path} from #{request.remote_ip}: #{result.reason}")
    human_check_failed(result)
  end

  def human_check_failed(_result)
    if request.format.json? || request.content_type&.include?("application/json")
      render json: { error: MESSAGE }, status: :unprocessable_entity
    else
      redirect_back_or_to human_check_fallback_path, alert: MESSAGE, status: :see_other
    end
  end

  def human_check_fallback_path
    root_path
  end
end
