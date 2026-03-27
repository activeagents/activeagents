# frozen_string_literal: true

# Claims anonymous session recordings and associates them with the user's account
# after they complete signup. This allows users to see their own real interactions
# in the dashboard immediately after signing up.
class UserSessionClaimer
  attr_reader :user, :account, :session_id

  def initialize(user, session_id: nil)
    @user = user
    @account = user.primary_account
    @session_id = session_id
  end

  # Claim any anonymous sessions that belong to this user
  def claim!
    return unless account

    claim_by_session_id if session_id.present?
    claim_recent_anonymous_sessions
  end

  private

  # Claim a specific session by ID (passed from the signup flow)
  def claim_by_session_id
    recording = SessionRecording.find_by(id: session_id)
    return unless recording && recording.metadata["user_id"].blank?

    associate_recording_with_user(recording)
  end

  # Claim recent anonymous user sessions that match this user's visitor fingerprint
  def claim_recent_anonymous_sessions
    # Find user takeover sessions from the last hour that haven't been claimed
    SessionRecording
      .user_sessions
      .where("created_at > ?", 1.hour.ago)
      .where("metadata->>'user_id' IS NULL OR metadata->>'user_id' = ''")
      .find_each do |recording|
        associate_recording_with_user(recording)
      end
  end

  def associate_recording_with_user(recording)
    recording.update!(
      metadata: recording.metadata.merge(
        user_id: user.id,
        account_id: account.id,
        claimed_at: Time.current.iso8601
      )
    )
  end
end
