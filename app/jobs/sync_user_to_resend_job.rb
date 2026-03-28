class SyncUserToResendJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)
    return if user.synced_to_resend?

    audience_id = ENV["RESEND_AUDIENCE_ID"]
    raise "RESEND_AUDIENCE_ID environment variable not set" if audience_id.blank?

    Resend.api_key = ENV["RESEND_API_KEY"]

    response = Resend::Contacts.create(
      audience_id: audience_id,
      email: user.email_address,
      first_name: user.first_name,
      last_name: user.last_name,
      unsubscribed: false
    )

    if response[:id].present?
      user.update!(synced_to_resend: true)
    else
      raise "Resend sync failed for user #{user_id}: #{response.inspect}"
    end
  end
end
