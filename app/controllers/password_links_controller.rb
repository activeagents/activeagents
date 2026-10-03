# Emails the signed-in user the password-reset link from Settings, which is
# how an account created through GitHub chooses its first password.
class PasswordLinksController < ApplicationController
  before_action :require_verified_user!
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to settings_path, alert: "Try again later." }

  def create
    PasswordsMailer.reset(Current.user).deliver_later
    redirect_to settings_path, notice: "We emailed you a link to set a password."
  end
end
