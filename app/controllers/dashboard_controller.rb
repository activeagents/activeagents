class DashboardController < ApplicationController
  layout "landing"
  before_action :authenticate_user!

  def index
  end
end
