module Api
  module V1
    class PlansController < ApplicationController
      skip_forgery_protection

      def index
        plans = Plan.active.order(:price_cents)
        render json: plans.as_json(only: [
          :id, :name, :slug, :price_cents, :annual_price_cents,
          :trial_days, :included_seats, :included_workspaces, :features
        ])
      end
    end
  end
end
