module Api
  module V1
    class PlansController < Api::BaseController
      allow_unauthenticated_access

      def index
        plans = Plan.active.order(:price_cents)
        render json: plans.map { |plan|
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
        }
      end
    end
  end
end
