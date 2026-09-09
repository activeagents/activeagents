# frozen_string_literal: true

require "test_helper"

class SyncLeadToResendJobTest < ActiveJob::TestCase
  # Stands in for Resend::Contacts, recording what the job sent.
  class FakeContacts
    attr_reader :calls

    def initialize(response)
      @response = response
      @calls = []
    end

    def create(**kwargs)
      @calls << kwargs
      @response
    end
  end

  setup do
    @lead = Lead.create!(name: "Jane Developer", email: "jane@example.com", service_type: "advisory")
  end

  teardown do
    SyncLeadToResendJob.contacts_client = nil
    ENV.delete("RESEND_AUDIENCE_ID")
    ENV.delete("RESEND_API_KEY")
  end

  test "marks the lead synced when Resend accepts the contact" do
    configure_resend(FakeContacts.new(id: "contact_123"))

    SyncLeadToResendJob.perform_now(@lead.id)

    assert @lead.reload.synced_to_resend?
  end

  test "splits the name into first and last for the Resend contact" do
    fake = configure_resend(FakeContacts.new(id: "contact_123"))

    SyncLeadToResendJob.perform_now(@lead.id)

    call = fake.calls.sole
    assert_equal "Jane", call[:first_name]
    assert_equal "Developer", call[:last_name]
    assert_equal "jane@example.com", call[:email]
    assert_equal "aud_test", call[:audience_id]
  end

  test "does not re-sync an already synced lead" do
    @lead.update!(synced_to_resend: true)
    fake = configure_resend(FakeContacts.new(id: "contact_123"))

    SyncLeadToResendJob.perform_now(@lead.id)

    assert_empty fake.calls
  end

  test "no-ops when Resend is not configured" do
    fake = FakeContacts.new(id: "contact_123")
    SyncLeadToResendJob.contacts_client = fake

    SyncLeadToResendJob.perform_now(@lead.id)

    assert_empty fake.calls
    assert_not @lead.reload.synced_to_resend?
  end

  test "raises when Resend rejects the contact" do
    configure_resend(FakeContacts.new(error: "bad request"))

    assert_raises(RuntimeError) { SyncLeadToResendJob.perform_now(@lead.id) }
    assert_not @lead.reload.synced_to_resend?
  end

  private

  def configure_resend(fake)
    ENV["RESEND_AUDIENCE_ID"] = "aud_test"
    ENV["RESEND_API_KEY"] = "re_test"
    SyncLeadToResendJob.contacts_client = fake
    fake
  end
end
