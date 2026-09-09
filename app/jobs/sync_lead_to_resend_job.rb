class SyncLeadToResendJob < ApplicationJob
  queue_as :default

  # Seam for tests: swap in a fake that responds to .create(**kwargs).
  class_attribute :contacts_client, default: nil

  def perform(lead_id)
    lead = Lead.find(lead_id)
    return if lead.synced_to_resend?

    audience_id = ENV["RESEND_AUDIENCE_ID"]
    return if audience_id.blank?

    api_key = ENV["RESEND_API_KEY"]
    return if api_key.blank?

    client = self.class.contacts_client
    unless client
      Resend.api_key = api_key
      client = Resend::Contacts
    end

    first_name, last_name = lead.name.split(" ", 2)

    response = client.create(
      audience_id: audience_id,
      email: lead.email,
      first_name: first_name,
      last_name: last_name,
      unsubscribed: false
    )

    if response[:id].present?
      lead.update!(synced_to_resend: true)
    else
      raise "Resend sync failed for lead #{lead_id}: #{response.inspect}"
    end
  end
end
