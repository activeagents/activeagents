# frozen_string_literal: true

class OnboardingController < ApplicationController
  before_action :require_authentication
  before_action :redirect_if_complete, only: [ :pending_verification, :complete_profile ]

  # GET /pending_verification
  def pending_verification
    if Current.user.email_verified?
      redirect_to complete_profile_path
    end
  end

  # GET /complete_profile
  def complete_profile
    unless Current.user.email_verified?
      redirect_to pending_verification_path
      return
    end

    if Current.user.profile_completed?
      redirect_to dashboard_path
      return
    end

    @user = Current.user
    @plans = Plan.active.order(:price_cents)
    @current_plan = @user.primary_account&.current_plan || Plan.find_by(slug: "free")
  end

  # PATCH /complete_profile
  def update_profile
    @user = Current.user

    if @user.complete_profile!(profile_params)
      # Handle plan selection if upgrading
      handle_plan_selection if params[:plan_slug].present? && params[:plan_slug] != "free"

      UserMailer.welcome(@user).deliver_later
      redirect_to dashboard_path, notice: "Welcome to Active Agent! Let's build your first agent."
    else
      @plans = Plan.active.order(:price_cents)
      render :complete_profile, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:user).permit(:first_name, :last_name, :company_name, :job_title, :password, :password_confirmation)
  end

  def handle_plan_selection
    plan = Plan.find_by(slug: params[:plan_slug])
    return unless plan&.paid?

    # Store selected plan for checkout after profile completion
    session[:selected_plan_slug] = plan.slug
  end

  def redirect_if_complete
    if Current.user.email_verified? && Current.user.profile_completed?
      redirect_to dashboard_path
    end
  end
end
