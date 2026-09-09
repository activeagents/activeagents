# frozen_string_literal: true

require "test_helper"

class SyncUserToResendJobTest < ActiveJob::TestCase
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
    @user = User.create!(email_address: "sync#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  teardown do
    SyncUserToResendJob.contacts_client = nil
    ENV.delete("RESEND_AUDIENCE_ID")
    ENV.delete("RESEND_API_KEY")
  end

  test "marks the user synced when Resend accepts the contact" do
    configure_resend(FakeContacts.new(id: "contact_123"))

    SyncUserToResendJob.perform_now(@user.id)

    assert @user.reload.synced_to_resend?
  end

  test "sends the user's email to the configured audience" do
    fake = configure_resend(FakeContacts.new(id: "contact_123"))

    SyncUserToResendJob.perform_now(@user.id)

    call = fake.calls.sole
    assert_equal @user.email_address, call[:email]
    assert_equal "aud_test", call[:audience_id]
    assert_equal false, call[:unsubscribed]
  end

  test "does not re-sync an already synced user" do
    @user.update!(synced_to_resend: true)
    fake = configure_resend(FakeContacts.new(id: "contact_123"))

    SyncUserToResendJob.perform_now(@user.id)

    assert_empty fake.calls
  end

  test "raises when the audience is not configured" do
    ENV["RESEND_API_KEY"] = "re_test"
    SyncUserToResendJob.contacts_client = FakeContacts.new(id: "contact_123")

    assert_raises(RuntimeError) { SyncUserToResendJob.perform_now(@user.id) }
  end

  test "raises when Resend rejects the contact" do
    configure_resend(FakeContacts.new(error: "bad request"))

    assert_raises(RuntimeError) { SyncUserToResendJob.perform_now(@user.id) }
    assert_not @user.reload.synced_to_resend?
  end

  private

  def configure_resend(fake)
    ENV["RESEND_AUDIENCE_ID"] = "aud_test"
    ENV["RESEND_API_KEY"] = "re_test"
    SyncUserToResendJob.contacts_client = fake
    fake
  end
end
