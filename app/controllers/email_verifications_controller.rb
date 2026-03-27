# frozen_string_literal: true

class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: [ :show ]
  before_action :set_user_by_token, only: [ :show ]

  # GET /verify_email?token=xxx
  def show
    if @user&.verify_email!(params[:token])
      start_new_session_for(@user) unless Current.session
      redirect_to complete_profile_path, notice: "Email verified! Let's complete your profile."
    else
      redirect_to root_path, alert: "Invalid or expired verification link."
    end
  end

  # POST /resend_verification
  def create
    if Current.user && !Current.user.email_verified?
      Current.user.send_verification_email!
      redirect_to pending_verification_path, notice: "Verification email sent!"
    else
      redirect_to root_path
    end
  end

  private

  def set_user_by_token
    @user = User.find_by(email_verification_token: params[:token])
  end
end
