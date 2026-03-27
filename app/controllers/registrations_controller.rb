# frozen_string_literal: true

class RegistrationsController < ApplicationController
  allow_unauthenticated_access

  def new
    @user = User.new
    @source = params[:source] # Track where signup came from (demo, newsletter, etc.)
  end

  def create
    # Handle both JSON (landing page signup) and HTML (full form) requests
    if request.format.json? || request.content_type&.include?("application/json")
      create_from_landing_page
    else
      create_from_form
    end
  end

  private

  # Simplified signup from landing page - email only
  # User will set password during profile completion after email verification
  def create_from_landing_page
    email = params[:email_address] || params.dig(:user, :email_address)

    # Check if user already exists
    existing_user = User.find_by(email_address: email)
    if existing_user
      if existing_user.email_verified?
        render json: { error: "This email is already registered. Please sign in." }, status: :unprocessable_entity
      else
        # Resend verification email
        existing_user.send_verification_email!
        render json: { success: true, redirect_url: pending_verification_path, message: "Verification email resent." }
      end
      return
    end

    # Create user with temporary password (will be set during profile completion)
    @user = User.new(
      email_address: email,
      password: SecureRandom.hex(16),
      signup_source: params[:source] || "landing_page"
    )

    if @user.save
      # Create default account/workspace
      account = Account.create!(name: "#{@user.display_name}'s Workspace", owner: @user)
      AccountMembership.create!(account: account, user: @user, role: "owner")

      # Send verification email
      @user.send_verification_email!

      # Start session so user can access pending verification page
      start_new_session_for(@user)

      render json: { success: true, redirect_url: pending_verification_path }
    else
      render json: { error: @user.errors.full_messages.first || "Registration failed" }, status: :unprocessable_entity
    end
  end

  # Full registration from form (with password)
  def create_from_form
    @user = User.new(user_params)

    if @user.save
      # Create default account/workspace
      account = Account.create!(name: "#{@user.display_name}'s Workspace", owner: @user)
      AccountMembership.create!(account: account, user: @user, role: "owner")

      # Send verification email
      @user.send_verification_email!

      # Start session so user can access pending verification page
      start_new_session_for(@user)

      redirect_to pending_verification_path, notice: "Check your email to verify your account!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def user_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
