class SubscriptionsController < ApplicationController
  before_action :require_authentication
  before_action :require_account!, except: [:checkout]
  before_action :ensure_account_for_checkout, only: [:checkout]

  def index
    subscription = current_account.active_subscription
    plan = current_account.current_plan

    render inertia: "Subscriptions/Index", props: {
      subscription: subscription ? subscription_props(subscription) : nil,
      plan: plan ? plan_props(plan) : nil,
      plans: Plan.active.order(:price_cents).map { |p| plan_props(p) },
      stripe_public_key: stripe_public_key
    }
  end

  def checkout
    plan = Plan.find(params[:plan_id])
    billing_interval = params[:billing_interval] || "monthly"

    price_id = case billing_interval
    when "annual"
      plan.stripe_annual_price_id
    else
      plan.stripe_monthly_price_id
    end

    unless price_id
      redirect_to plans_path, alert: "This plan is not available for purchase."
      return
    end

    pay_customer = current_account.set_payment_processor(:stripe)
    checkout_session = pay_customer.checkout(
      mode: "subscription",
      line_items: [ { price: price_id, quantity: 1 } ],
      success_url: subscriptions_url,
      cancel_url: plans_url,
      subscription_data: plan.trial_days.positive? ? { trial_period_days: plan.trial_days } : {}
    )

    # For Inertia requests, return the URL as JSON so frontend can redirect
    if request.headers["X-Inertia"]
      render json: { checkout_url: checkout_session.url }
    else
      redirect_to checkout_session.url, allow_other_host: true
    end
  end

  def billing_portal
    pay_customer = current_account.payment_processor
    unless pay_customer
      redirect_to subscriptions_path, alert: "No billing information found."
      return
    end

    portal_session = pay_customer.billing_portal(return_url: subscriptions_url)
    redirect_to portal_session.url, allow_other_host: true
  end

  def change_plan
    plan = Plan.find(params[:plan_id])
    billing_interval = params[:billing_interval] || "monthly"
    subscription = current_account.active_subscription

    unless subscription
      redirect_to subscriptions_path, alert: "No active subscription found."
      return
    end

    price_id = case billing_interval
    when "annual"
      plan.stripe_annual_price_id
    else
      plan.stripe_monthly_price_id
    end

    subscription.swap(price_id)
    redirect_to subscriptions_path, notice: "Plan changed to #{plan.name}."
  end

  def resume
    subscription = current_account.active_subscription

    unless subscription
      redirect_to subscriptions_path, alert: "No subscription found to resume."
      return
    end

    subscription.resume
    redirect_to subscriptions_path, notice: "Subscription resumed."
  end

  def destroy
    subscription = current_account.active_subscription

    unless subscription
      redirect_to subscriptions_path, alert: "No active subscription found."
      return
    end

    subscription.cancel
    redirect_to subscriptions_path, notice: "Subscription cancelled. Access continues until the end of the billing period."
  end

  private

  def current_user
    Current.session&.user
  end

  def current_account
    @current_account ||= current_user&.primary_account
  end

  def require_account!
    unless current_account
      redirect_to dashboard_path, alert: "Please set up an account first."
    end
  end

  def ensure_account_for_checkout
    return if current_account

    # Create an account for the user if they don't have one
    @current_account = current_user.owned_accounts.create!(
      name: "#{current_user.email_address.split('@').first}'s Account"
    )
  end

  def stripe_public_key
    Rails.application.credentials.dig(:stripe, :public_key) || ENV["STRIPE_PUBLIC_KEY"]
  end

  def subscription_props(subscription)
    {
      id: subscription.id,
      processor_plan: subscription.processor_plan,
      status: subscription.status,
      trial_ends_at: subscription.trial_ends_at&.iso8601,
      ends_at: subscription.ends_at&.iso8601,
      created_at: subscription.created_at.iso8601,
      on_trial: subscription.on_trial?,
      cancelled: subscription.ends_at.present?,
      active: subscription.active?
    }
  end

  def plan_props(plan)
    {
      id: plan.id,
      name: plan.name,
      slug: plan.slug,
      price_cents: plan.price_cents,
      price_dollars: plan.price_dollars,
      annual_price_cents: plan.annual_price_cents,
      annual_price_dollars: plan.annual_price_dollars,
      trial_days: plan.trial_days,
      included_seats: plan.included_seats,
      included_workspaces: plan.included_workspaces,
      features: plan.features,
      free: plan.free?
    }
  end
end
