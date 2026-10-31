class HomeController < ApplicationController
  allow_unauthenticated_access

  def index
    return redirect_to hunts_path if authenticated?

    @plans = Plan.all
  end
end
