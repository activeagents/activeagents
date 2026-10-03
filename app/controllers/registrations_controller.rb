# frozen_string_literal: true

class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 10.minutes, only: :create

  def new
    @user = User.new
    @source = params[:source]
  end

  def create
    # Handle landing page signup (email at root level, JSON, or no nested user params)
    # vs full registration form (nested user params with password)
    if params[:source] == "newsletter"
      NewsletterSubscription.subscribe!(params[:email_address])
      respond_to do |format|
        format.json { render json: { success: true, message: "Check your email to confirm your newsletter subscription." } }
        format.html { redirect_to root_path(anchor: "newsletter"), notice: "Check your email to confirm your newsletter subscription." }
      end
    elsif landing_page_signup?
      create_from_landing_page
    else
      create_from_form
    end
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: "This email is already registered. Please sign in." }, status: :unprocessable_entity
  end

  def landing_page_signup?
    # JSON requests are always from landing page
    return true if request.format.json? || request.content_type&.include?("application/json")
    # Root-level email_address (not nested under :user) indicates landing page form
    return true if params[:email_address].present? && !params[:user].present?
    false
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
        respond_to do |format|
          format.html { redirect_to new_session_path, alert: "This email is already registered. Please sign in." }
          format.json { render json: { error: "This email is already registered. Please sign in." }, status: :unprocessable_entity }
        end
      else
        # Resend verification email
        existing_user.send_verification_email!
        respond_to do |format|
          format.html { redirect_to new_session_path, notice: "Verification email resent. Open the link in your email to continue." }
          format.json { render json: { success: true, redirect_url: new_session_path, message: "Verification email resent. Open the link in your email to continue." } }
        end
      end
      return
    end

    # Create user with temporary password (will be set during profile completion)
    @user = User.new(
      email_address: email,
      password: SecureRandom.hex(16),
      signup_source: "public_signup"
    )

    if @user.save_with_workspace
      # Send verification email
      @user.send_verification_email!

      # Start session so user can access pending verification page
      start_new_session_for(@user)

      respond_to do |format|
        format.html { redirect_to pending_verification_path, notice: "Check your email to verify your account!" }
        format.json { render json: { success: true, redirect_url: pending_verification_path } }
      end
    else
      respond_to do |format|
        format.html { redirect_to root_path(anchor: "signup"), alert: @user.errors.full_messages.first || "Registration failed" }
        format.json { render json: { error: @user.errors.full_messages.first || "Registration failed" }, status: :unprocessable_entity }
      end
    end
  end

  # Full registration from form (with password)
  def create_from_form
    @user = User.new(user_params.merge(signup_source: "public_signup"))

    if @user.save_with_workspace
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
