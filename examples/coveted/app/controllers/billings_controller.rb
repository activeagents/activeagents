class BillingsController < ApplicationController
  def show
    @plans = Plan.all
    @plan = current_user.plan
    @charges = current_user.charges.recent.includes(:discovery_run).limit(50)
    @month_to_date = current_user.month_to_date_cents
  end

  def subscribe
    plan = Plan.find_by(params[:plan])
    return redirect_to billing_path, alert: "That isn't a subscription plan." unless plan&.subscription?

    Billing.subscribe!(current_user, plan)
    redirect_to billing_path, notice: "You're on #{plan.name}: #{helpers.money(plan.monthly_cents)} a month, #{helpers.fee_label(plan)}."
  end

  def cancel
    Billing.cancel!(current_user)
    redirect_to billing_path, status: :see_other,
                notice: "Subscription cancelled. You're back on pay per check, and scheduled checks run weekly at most."
  end
end
