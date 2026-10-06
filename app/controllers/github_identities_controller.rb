# Connects GitHub to the signed-in user from Settings, and disconnects it.
# GithubSessionsController#callback completes a connect.
class GithubIdentitiesController < ApplicationController
  include GithubAuthorization

  before_action :require_verified_user!
  before_action :require_github_configured, only: :create
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to settings_path, alert: "Try again later." }

  def create
    redirect_to_github("connect")
  end

  # Refused while GitHub is the account's only way to sign in.
  def destroy
    identity = Current.user.github_identity
    if identity.nil?
      redirect_to settings_path
    elsif !Current.user.password_set?
      redirect_to settings_path, alert: "Set a password before disconnecting GitHub, or you won't be able to sign in."
    else
      identity.destroy!
      redirect_to settings_path, notice: "Disconnected GitHub."
    end
  end
end
