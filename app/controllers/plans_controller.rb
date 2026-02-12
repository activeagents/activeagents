class PlansController < ApplicationController
  # GET /plans
  def index
    plans = Plan.active.order(:price_cents)

    render inertia: "Plans/Index", props: {
      plans: plans.map { |plan|
        {
          id: plan.id,
          name: plan.name,
          slug: plan.slug,
          price_cents: plan.price_cents,
          annual_price_cents: plan.annual_price_cents,
          trial_days: plan.trial_days,
          included_seats: plan.included_seats,
          included_workspaces: plan.included_workspaces,
          features: plan.features,
          free: plan.free?,
          annual_savings_percent: plan.annual_savings_percent
        }
      }
    }
  end
end
