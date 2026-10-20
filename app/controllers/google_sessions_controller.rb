# Signs people in with Google, and receives Google's callback for both a
# sign-in and a Settings "Connect Google" (GoogleIdentitiesController).
#
# A sign-in never attaches Google to an existing account by email. Only a
# signed-in user connects Google, from Settings.
class GoogleSessionsController < ApplicationController
  include GoogleAuthorization

  allow_unauthenticated_access
  before_action :require_google_configured
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def create
    redirect_to_google("sign_in")
  end

  def callback
    pending = take_google_authorization(params[:state])
    return redirect_to(new_session_path, alert: "That Google sign-in is no longer valid. Try again.") unless pending

    connecting = pending["intent"] == "connect"
    if connecting && !started_this_connect?(pending)
      return redirect_to(new_session_path, alert: "Sign in again to connect Google.")
    end
    if params[:error].present? || params[:code].blank?
      return redirect_to(return_path(connecting), alert: connecting ? "Connecting Google was cancelled." : "Google sign-in was cancelled.")
    end

    google = GoogleSignIn.identity_for(code: params[:code].to_s, redirect_uri: google_callback_url, code_verifier: pending["code_verifier"].to_s)
    connecting ? connect(google) : sign_in(google)
  rescue GoogleSignIn::Error => error
    Rails.logger.warn("Google sign-in failed: #{error.message}")
    redirect_to return_path(connecting), alert: "Google didn't confirm your account. Try again."
  end

  private

  def return_path(connecting)
    connecting ? settings_path : new_session_path
  end

  def started_this_connect?(pending)
    resume_session
    Current.session.present? && Current.user.id == pending["user_id"] && Current.session.id == pending["session_id"]
  end

  def sign_in(google)
    if (identity = UserIdentity.find_by(provider: "google", uid: google.uid))
      identity.update!(email: google.email)
      start_new_session_for(identity.user)
      redirect_to after_authentication_url
    elsif google.email.blank?
      redirect_to new_session_path, alert: "Your Google account's email address isn't verified. Verify it with Google, or sign up with your email."
    elsif User.exists?(email_address: google.email)
      session[:return_to_after_authenticating] = settings_url
      redirect_to new_session_path, notice: "An account already uses #{google.email}. Sign in with your password, then connect Google from Settings."
    else
      sign_up(google)
    end
  end

  # Creates the account the way an email signup does, minus the verification
  # email: Google has verified the address. Profile completion and plan
  # selection follow as usual.
  def sign_up(google)
    user = build_user(google)
    if user.save_with_workspace
      start_new_session_for(user)
      redirect_to complete_profile_path, notice: "Signed in with Google. Finish setting up your workspace."
    else
      redirect_to new_session_path, alert: "We couldn't create an account from Google: #{user.errors.full_messages.to_sentence}"
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to new_session_path, alert: "An account for this Google account or email was just created. Sign in to continue."
  end

  def build_user(google)
    first_name, last_name = google.given_name.presence, google.family_name.presence
    first_name, last_name = google.name.to_s.strip.split(/\s+/, 2) if first_name.nil? && last_name.nil?
    user = User.new(email_address: google.email, email_verified: true, first_name: first_name, last_name: last_name, signup_source: "google")
    user.assign_random_password
    user.identities.build(provider: "google", uid: google.uid, email: google.email)
    user
  end

  def connect(google)
    identity = UserIdentity.find_by(provider: "google", uid: google.uid)
    if identity && identity.user_id != Current.user.id
      redirect_to settings_path, alert: "That Google account is connected to another ActiveAgents account."
    elsif identity
      identity.update!(email: google.email)
      redirect_to settings_path, notice: "Google is already connected."
    elsif (current = Current.user.google_identity)
      redirect_to settings_path, alert: "Disconnect #{label(current)} before connecting another Google account."
    else
      Current.user.identities.create!(provider: "google", uid: google.uid, email: google.email)
      redirect_to settings_path, notice: "Connected Google as #{label(google)}."
    end
  # A concurrent connect, by this user or another, can claim either unique
  # index between the checks above and the insert.
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    if (current = Current.user.reload_google_identity)
      redirect_to settings_path, notice: "Google is already connected as #{label(current)}."
    else
      redirect_to settings_path, alert: "That Google account is connected to another ActiveAgents account."
    end
  end

  # How a Google account is named to the person: by its address, which is all
  # Google gives that they would recognize.
  def label(account)
    account.email.presence || "the connected Google account"
  end
end
