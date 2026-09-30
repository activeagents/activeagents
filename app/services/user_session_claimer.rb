# frozen_string_literal: true

# Claims anonymous session recordings and associates them with the user's account
# after they complete signup. This allows users to see their own real interactions
# in the dashboard immediately after signing up.
class UserSessionClaimer
  attr_reader :user, :account, :session_id

  def initialize(user, session_id: nil, account: user.primary_account)
    @user = user
    @account = account
    @session_id = session_id
  end

  # Claim any anonymous sessions that belong to this user
  def claim!
    return unless account

    claim_by_session_id if session_id.present?
  end

  private

  # Claim a specific session by ID (passed from the signup flow)
  def claim_by_session_id
    recording = SessionRecording.find_by(id: session_id)
    return unless recording && recording.user_id.nil? && recording.account_id.nil?

    associate_recording_with_user(recording)
  end

  def associate_recording_with_user(recording)
    recording.update!(
      user_id: user.id, account_id: account.id,
      metadata: recording.metadata.merge(
        user_id: user.id,
        account_id: account.id,
        claimed_at: Time.current.iso8601
      )
    )
  end
end
