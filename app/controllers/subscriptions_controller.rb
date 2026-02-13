class SubscriptionsController < ApplicationController
  layout "landing"
  before_action :authenticate_user!
  before_action :require_account!

  # GET /subscriptions
  def index
    @current_plan = current_account.current_plan
    @subscription = current_account.payment_processor&.subscription
    @plans = Plan.active.order(:price_cents)
  end

  # POST /subscriptions/checkout
  def checkout
    plan = Plan.find_by!(slug: params[:plan])
    price_id = params[:interval] == "annual" ? plan.stripe_annual_price_id : plan.stripe_monthly_price_id

    unless price_id
      redirect_to subscriptions_path, alert: "This plan is not available for self-service checkout."
      return
    end

    pay_customer = current_account.set_payment_processor(:stripe)
    pay_customer.update_customer!

    checkout_options = {
      mode: "subscription",
      line_items: price_id,
      success_url: subscriptions_url,
      cancel_url: subscriptions_url,
      allow_promotion_codes: true
    }

    if plan.trial_days > 0
      checkout_options[:subscription_data] = { trial_period_days: plan.trial_days }
    end

    checkout_session = pay_customer.checkout(**checkout_options)

    redirect_to checkout_session.url, allow_other_host: true
  end

  # POST /subscriptions/billing_portal
  def billing_portal
    pay_customer = current_account.payment_processor

    unless pay_customer
      redirect_to subscriptions_path, alert: "No billing information found."
      return
    end

    portal_session = pay_customer.billing_portal(return_url: subscriptions_url)
    redirect_to portal_session.url, allow_other_host: true
  end

  # DELETE /subscriptions/:id
  def destroy
    subscription = current_account.payment_processor&.subscription

    if subscription&.active?
      subscription.cancel
      redirect_to subscriptions_path, notice: "Subscription will be canceled at the end of the billing period."
    else
      redirect_to subscriptions_path, alert: "No active subscription found."
    end
  end

  # PATCH /subscriptions/change_plan
  def change_plan
    plan = Plan.find_by!(slug: params[:plan])
    subscription = current_account.payment_processor&.subscription
    price_id = params[:interval] == "annual" ? plan.stripe_annual_price_id : plan.stripe_monthly_price_id

    if subscription&.active? && price_id
      subscription.swap(price_id)
      redirect_to subscriptions_path, notice: "Plan updated to #{plan.name}."
    else
      redirect_to checkout_subscriptions_path(plan: plan.slug, interval: params[:interval])
    end
  end

  # POST /subscriptions/resume
  def resume
    subscription = current_account.payment_processor&.subscription

    if subscription&.canceled? && subscription&.on_grace_period?
      subscription.resume
      redirect_to subscriptions_path, notice: "Subscription resumed."
    else
      redirect_to subscriptions_path, alert: "Unable to resume subscription."
    end
  end

end
