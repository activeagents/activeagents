# Used to send a person through GitHub's authorization and to recognize the
# callback that brings them back.
#
# The pending authorization lives in this browser's session: a random state,
# what the round trip is for (`intent`), the signed-in user and session that
# started it (nil for a sign-in), and an expiry. A callback consumes it whether
# or not the state matches, so each state is good for one callback.
module GithubAuthorization
  extend ActiveSupport::Concern

  PENDING_KEY = :github_authorization
  STATE_TTL = 10.minutes

  private

  def require_github_configured
    head :not_found unless GithubSignIn.configured?
  end

  def redirect_to_github(intent)
    state = SecureRandom.urlsafe_base64(32)
    session[PENDING_KEY] = {
      "state" => state,
      "intent" => intent,
      "user_id" => Current.user&.id,
      "session_id" => Current.session&.id,
      "expires_at" => STATE_TTL.from_now.to_i
    }
    redirect_to GithubSignIn.authorize_url(state: state, redirect_uri: github_callback_url), allow_other_host: true
  end

  # Returns the pending authorization `state` belongs to, or nil when there is
  # none, it expired, or the state differs.
  def take_github_authorization(state)
    pending = session.delete(PENDING_KEY)
    return unless pending.is_a?(Hash) && state.is_a?(String)
    return unless pending["expires_at"].to_i > Time.current.to_i

    pending if ActiveSupport::SecurityUtils.secure_compare(pending["state"].to_s, state)
  end
end
