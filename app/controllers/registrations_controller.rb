# frozen_string_literal: true

class RegistrationsController < ApplicationController
  allow_unauthenticated_access

  def new
    @user = User.new
    @source = params[:source] # Track where signup came from (demo, newsletter, etc.)
  end

  def create
    # Handle landing page signup (email at root level, JSON, or no nested user params)
    # vs full registration form (nested user params with password)
    if landing_page_signup?
      create_from_landing_page
    else
      create_from_form
    end
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
        start_new_session_for(existing_user)
        respond_to do |format|
          format.html { redirect_to pending_verification_path, notice: "Verification email resent." }
          format.json { render json: { success: true, redirect_url: pending_verification_path, message: "Verification email resent." } }
        end
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

      # Sync contact to Loops for marketing email
      SyncUserToLoopsJob.perform_later(@user.id)

      # Start session so user can access pending verification page
      start_new_session_for(@user)

      # Store recording ID if user signed up from an active session recording
      store_signup_recording_id

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
    @user = User.new(user_params)

    if @user.save
      # Create default account/workspace
      account = Account.create!(name: "#{@user.display_name}'s Workspace", owner: @user)
      AccountMembership.create!(account: account, user: @user, role: "owner")

      # Send verification email
      @user.send_verification_email!

      # Sync contact to Loops for marketing email
      SyncUserToLoopsJob.perform_later(@user.id)

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

  # Store the session recording ID so we can claim it after profile completion
  def store_signup_recording_id
    recording_id = params[:recording_id] || params[:session_recording_id]
    session[:signup_recording_id] = recording_id if recording_id.present?
  end
end
