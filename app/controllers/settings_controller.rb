# The signed-in user's account settings: how they sign in.
class SettingsController < ApplicationController
  before_action :require_verified_user!
  layout "pilot"

  def show
    @user = Current.user
    @github_identity = @user.github_identity
  end
end
