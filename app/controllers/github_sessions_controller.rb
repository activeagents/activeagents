# Signs people in with GitHub, and receives GitHub's callback for both a
# sign-in and a Settings "Connect GitHub" (GithubIdentitiesController).
#
# A sign-in never attaches GitHub to an existing account by email. Only a
# signed-in user connects GitHub, from Settings.
class GithubSessionsController < ApplicationController
  include GithubAuthorization

  allow_unauthenticated_access
  before_action :require_github_configured
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def create
    redirect_to_github("sign_in")
  end

  def callback
    pending = take_github_authorization(params[:state])
    return redirect_to(new_session_path, alert: "That GitHub sign-in is no longer valid. Try again.") unless pending

    connecting = pending["intent"] == "connect"
    if connecting && !started_this_connect?(pending)
      return redirect_to(new_session_path, alert: "Sign in again to connect GitHub.")
    end
    if params[:error].present? || params[:code].blank?
      return redirect_to(return_path(connecting), alert: connecting ? "Connecting GitHub was cancelled." : "GitHub sign-in was cancelled.")
    end

    github = GithubSignIn.identity_for(code: params[:code].to_s, redirect_uri: github_callback_url)
    connecting ? connect(github) : sign_in(github)
  rescue GithubSignIn::Error => error
    Rails.logger.warn("GitHub sign-in failed: #{error.message}")
    redirect_to return_path(connecting), alert: "GitHub didn't confirm your account. Try again."
  end

  private

  def return_path(connecting)
    connecting ? settings_path : new_session_path
  end

  def started_this_connect?(pending)
    resume_session
    Current.session.present? && Current.user.id == pending["user_id"] && Current.session.id == pending["session_id"]
  end

  def sign_in(github)
    if (identity = UserIdentity.find_by(provider: "github", uid: github.uid))
      identity.update!(login: github.login, email: github.email)
      start_new_session_for(identity.user)
      redirect_to after_authentication_url
    elsif github.email.blank?
      redirect_to new_session_path, alert: "Your GitHub account has no verified primary email address. Verify one on GitHub, or sign up with your email."
    elsif User.exists?(email_address: github.email)
      session[:return_to_after_authenticating] = settings_url
      redirect_to new_session_path, notice: "An account already uses #{github.email}. Sign in with your password, then connect GitHub from Settings."
    else
      sign_up(github)
    end
  end

  # Creates the account the way an email signup does, minus the verification
  # email: GitHub has verified the address. Profile completion and plan
  # selection follow as usual.
  def sign_up(github)
    user = build_user(github)
    if user.save_with_workspace
      start_new_session_for(user)
      redirect_to complete_profile_path, notice: "Signed in with GitHub. Finish setting up your workspace."
    else
      redirect_to new_session_path, alert: "We couldn't create an account from GitHub: #{user.errors.full_messages.to_sentence}"
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to new_session_path, alert: "An account for this GitHub account or email was just created. Sign in to continue."
  end

  def build_user(github)
    first_name, last_name = github.name.to_s.strip.split(/\s+/, 2)
    user = User.new(email_address: github.email, email_verified: true, first_name: first_name, last_name: last_name, signup_source: "github")
    user.assign_random_password
    user.identities.build(provider: "github", uid: github.uid, login: github.login, email: github.email)
    user
  end

  def connect(github)
    identity = UserIdentity.find_by(provider: "github", uid: github.uid)
    if identity && identity.user_id != Current.user.id
      redirect_to settings_path, alert: "That GitHub account is connected to another ActiveAgents account."
    elsif identity
      identity.update!(login: github.login, email: github.email)
      redirect_to settings_path, notice: "GitHub is already connected."
    elsif (current = Current.user.github_identity)
      redirect_to settings_path, alert: "Disconnect @#{current.login} before connecting another GitHub account."
    else
      Current.user.identities.create!(provider: "github", uid: github.uid, login: github.login, email: github.email)
      redirect_to settings_path, notice: "Connected GitHub as @#{github.login}."
    end
  # A concurrent connect, by this user or another, can claim either unique
  # index between the checks above and the insert.
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    if (current = Current.user.reload_github_identity)
      redirect_to settings_path, notice: "GitHub is already connected as @#{current.login}."
    else
      redirect_to settings_path, alert: "That GitHub account is connected to another ActiveAgents account."
    end
  end
end
