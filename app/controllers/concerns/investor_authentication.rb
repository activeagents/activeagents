module InvestorAuthentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_investor, :investor_authenticated?
  end

  class_methods do
    def allow_unauthenticated_investor_access(**options)
      skip_before_action :require_investor_authentication, **options
    end
  end

  private

  def current_investor
    @current_investor ||= find_investor_by_session
  end

  def investor_authenticated?
    current_investor.present?
  end

  def require_investor_authentication
    unless investor_authenticated?
      session[:investor_return_to] = request.url
      redirect_to investor_portal_login_path
    end
  end

  def find_investor_by_session
    Investor.find_by(id: session[:investor_id]) if session[:investor_id]
  end

  def start_investor_session(investor)
    session[:investor_id] = investor.id
    investor.update!(last_accessed_at: Time.current)
  end

  def terminate_investor_session
    session.delete(:investor_id)
    @current_investor = nil
  end

  def after_investor_authentication_url
    session.delete(:investor_return_to) || investor_portal_dashboard_path
  end
end
