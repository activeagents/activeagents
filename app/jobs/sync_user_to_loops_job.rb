class SyncUserToLoopsJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)
    return if user.synced_to_loops?

    response = Faraday.post(
      "https://app.loops.so/api/v1/contacts/create",
      {
        email: user.email_address,
        firstName: user.first_name,
        lastName: user.last_name,
        source: user.signup_source,
        userGroup: "waitlist"
      }.to_json,
      {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{ENV['LOOPS_API_KEY']}"
      }
    )

    if response.success?
      user.update!(synced_to_loops: true)
    else
      raise "Loops sync failed for user #{user_id}: #{response.status} #{response.body}"
    end
  end
end
