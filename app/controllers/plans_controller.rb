class PlansController < ApplicationController
  allow_unauthenticated_access
  before_action :set_current_session

  def index
    plans = Plan.active.order(:price_cents)
    current_user = Current.session&.user
    account = current_user&.primary_account

    render inertia: "Plans/Index", props: {
      plans: plans.map { |plan| plan_props(plan) },
      current_plan: account&.current_plan&.then { |p| plan_props(p) },
      signed_in: current_user.present?
    }
  end

  private

  def set_current_session
    resume_session
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
