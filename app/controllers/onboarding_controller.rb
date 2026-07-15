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

      # Claim any anonymous session recordings from the user's signup journey
      claim_user_sessions

      UserMailer.welcome(@user).deliver_later

      # A paid plan selection continues straight into Stripe checkout;
      # otherwise land on the free dashboard.
      if (checkout_url = pending_plan_checkout_url)
        redirect_to checkout_url, allow_other_host: true
      else
        redirect_to dashboard_path, notice: "Welcome to Active Agent! Let's build your first agent."
      end
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

  # Builds a Stripe Checkout session for the plan chosen on the
  # complete-profile page. Returns nil for free/unknown plans or when Stripe
  # isn't configured, so onboarding never hard-fails on billing — the user
  # lands on the dashboard and can upgrade from /pricing instead.
  def pending_plan_checkout_url
    slug = session.delete(:selected_plan_slug)
    return nil unless slug

    plan = Plan.find_by(slug: slug)
    return nil unless plan&.paid?

    account = Current.user.primary_account
    return nil unless account

    price_id = plan.stripe_monthly_price_id
    return nil unless price_id

    pay_customer = account.set_payment_processor(:stripe)
    pay_customer.checkout(
      mode: "subscription",
      line_items: [ { price: price_id, quantity: 1 } ],
      success_url: subscriptions_url,
      cancel_url: dashboard_url,
      subscription_data: plan.trial_days.positive? ? { trial_period_days: plan.trial_days } : {}
    ).url
  rescue => e
    Rails.logger.error("Onboarding checkout failed for user #{Current.user.id}: #{e.message}")
    nil
  end

  def redirect_if_complete
    if Current.user.email_verified? && Current.user.profile_completed?
      redirect_to dashboard_path
    end
  end

  def claim_user_sessions
    # Pass the session recording ID if it was stored during signup
    UserSessionClaimer.new(@user, session_id: session[:signup_recording_id]).claim!
    session.delete(:signup_recording_id)
  rescue => e
    # Don't fail onboarding if session claiming fails
    Rails.logger.error("Failed to claim sessions for user #{@user.id}: #{e.message}")
  end
end
