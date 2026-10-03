class WorkspaceInvitationsController < ApplicationController
  allow_unauthenticated_access
  layout "pilot"
  before_action :private_response
  before_action :resume_session
  before_action :load_invitation
  rate_limit to: 20, within: 3.minutes, only: :create

  def show
    render invitation_template
  end

  def create
    invitation = AcceptWorkspaceInvitation.call(token: params[:token], signed_in_user: Current.user,
      password: params[:password], password_confirmation: params[:password_confirmation])
    # Rotate the login and explicitly select the invited workspace.
    Current.session&.destroy!
    start_new_session_for(invitation.accepted_by, account: invitation.account)
    redirect_to workspace_path, notice: accepted_notice(invitation)
  rescue AcceptWorkspaceInvitation::SignInRequired => error
    flash.now[:alert] = error.message
    render invitation_template, status: :forbidden
  rescue AcceptWorkspaceInvitation::NoSeatAvailable => error
    flash.now[:alert] = error.message
    render invitation_template, status: :conflict
  rescue AcceptWorkspaceInvitation::Invalid, ProAccess::NotAuthorized
    render :unavailable, status: :gone
  rescue ActiveRecord::RecordInvalid => error
    flash.now[:alert] = error.record.errors.full_messages.to_sentence
    render invitation_template, status: :unprocessable_entity
  end

  private

  def private_response
    response.headers["Cache-Control"] = "no-store"
    # strict-origin sends only the origin as the Referer, so the token in the
    # URL never leaves in one, and browsers still send a real Origin with the
    # accept form, which Rails' forgery protection checks.
    response.headers["Referrer-Policy"] = "strict-origin"
  end

  def load_invitation
    @invitation = WorkspaceInvitation.for_token(params[:token])
    unless @invitation&.usable? && @invitation.inviter_authorized?
      render :unavailable, status: :gone
      return
    end
    @existing_user = User.exists?(email_address: @invitation.email_address)
    if @existing_user && !Current.user
      session[:return_to_after_authenticating] = workspace_invitation_path(token: params[:token])
    end
  end

  def invitation_template
    @invitation.teammate? ? :teammate : :show
  end

  def accepted_notice(invitation)
    if invitation.teammate?
      "Welcome to #{invitation.account.name}. You joined as #{invitation.role == "admin" ? "an admin" : "a member"}."
    else
      "Welcome to #{invitation.account.name}. Your Pro pilot access is ready."
    end
  end
end
