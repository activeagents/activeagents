class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    render inertia: "Dashboard", props: {
      user: {
        name: current_user.name,
        email: current_user.email
      },
      account: account_props
    }
  end

  private

  def account_props
    return nil unless current_account

    {
      name: current_account.name,
      plan: current_account.current_plan&.name,
      subscribed: current_account.subscribed?,
      on_trial: current_account.on_trial?
    }
  end
end
