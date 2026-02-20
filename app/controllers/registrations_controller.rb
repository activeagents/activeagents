# frozen_string_literal: true

class RegistrationsController < ApplicationController
  allow_unauthenticated_access

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      account = Account.create!(name: "#{@user.display_name}'s Account", owner: @user)
      AccountMembership.create!(account: account, user: @user, role: "owner")

      start_new_session_for(@user)
      redirect_to dashboard_path, notice: "Welcome! Your account has been created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
