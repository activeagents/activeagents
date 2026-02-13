class PlansController < ApplicationController
  layout "landing"

  # GET /plans
  def index
    @plans = Plan.active.order(:price_cents)
  end
end
