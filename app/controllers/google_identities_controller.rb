# Connects Google to the signed-in user from Settings, and disconnects it.
# GoogleSessionsController#callback completes a connect.
class GoogleIdentitiesController < ApplicationController
  include GoogleAuthorization

  before_action :require_verified_user!
  before_action :require_google_configured, only: :create
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to settings_path, alert: "Try again later." }

  def create
    redirect_to_google("connect")
  end

  # Refused while Google is the account's only way to sign in.
  def destroy
    identity = Current.user.google_identity
    if identity.nil?
      redirect_to settings_path
    elsif !Current.user.signs_in_without?(identity)
      redirect_to settings_path, alert: "Set a password before disconnecting Google, or you won't be able to sign in."
    else
      identity.destroy!
      redirect_to settings_path, notice: "Disconnected Google."
    end
  end
end
