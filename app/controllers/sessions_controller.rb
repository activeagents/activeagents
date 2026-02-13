class SessionsController < ApplicationController
  layout "landing"

  def new
  end

  def create
    user = User.find_by(email: params[:email])

    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      session[:account_id] = user.default_account&.id
      redirect_to dashboard_path, notice: "Signed in successfully."
    else
      redirect_to new_session_path, alert: "Invalid email or password."
    end
  end

  def destroy
    session.delete(:user_id)
    session.delete(:account_id)
    redirect_to root_path, notice: "Signed out."
  end
end
