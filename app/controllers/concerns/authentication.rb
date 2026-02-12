module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :current_account, :user_signed_in?
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def current_account
    @current_account ||= if session[:account_id]
      current_user&.accounts&.find_by(id: session[:account_id]) ||
        current_user&.default_account
    else
      current_user&.default_account
    end
  end

  def user_signed_in?
    current_user.present?
  end

  def authenticate_user!
    unless user_signed_in?
      respond_to do |format|
        format.html { redirect_to new_session_path, alert: "Please sign in to continue." }
        format.json { render json: { error: "Unauthorized" }, status: :unauthorized }
      end
    end
  end

  def require_account!
    authenticate_user!
    return unless user_signed_in?

    unless current_account
      redirect_to new_account_path, alert: "Please create or join an account."
    end
  end
end
