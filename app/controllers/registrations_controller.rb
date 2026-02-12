class RegistrationsController < ApplicationController
  def new
    render inertia: "Auth/SignUp"
  end

  def create
    user = User.new(user_params)

    if user.save
      account = user.owned_accounts.create!(name: "#{user.name}'s Team")
      AccountMembership.create!(account: account, user: user, role: "owner")

      session[:user_id] = user.id
      session[:account_id] = account.id
      redirect_to dashboard_path, notice: "Account created successfully."
    else
      redirect_to new_registration_path, alert: user.errors.full_messages.to_sentence
    end
  end

  private

  def user_params
    params.permit(:name, :email, :password, :password_confirmation)
  end
end
