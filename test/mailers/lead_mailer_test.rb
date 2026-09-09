# frozen_string_literal: true

require "test_helper"

class LeadMailerTest < ActionMailer::TestCase
  def build_lead(**overrides)
    Lead.create!({
      name: "Jane Developer",
      email: "jane@example.com",
      company: "Acme Inc.",
      service_type: "advisory",
      message: "We want help shipping agents."
    }.merge(overrides))
  end

  test "notification routes advisory inquiries to consulting" do
    mail = LeadMailer.notification(build_lead)

    assert_equal [ "consulting@activeagents.ai" ], mail.to
    assert_match "Advisory", mail.subject
    assert_match "Jane Developer", mail.subject
  end

  test "notification routes workshop inquiries to workshops" do
    mail = LeadMailer.notification(build_lead(service_type: "workshop"))
    assert_equal [ "workshops@activeagents.ai" ], mail.to
  end

  test "notification routes development inquiries to dev" do
    mail = LeadMailer.notification(build_lead(service_type: "development"))
    assert_equal [ "dev@activeagents.ai" ], mail.to
  end

  test "notification routes enterprise inquiries to sales" do
    mail = LeadMailer.notification(build_lead(service_type: "enterprise"))
    assert_equal [ "sales@activeagents.ai" ], mail.to
  end

  test "notification replies to the lead so we can answer directly" do
    mail = LeadMailer.notification(build_lead)
    assert_equal [ "jane@example.com" ], mail.reply_to
  end

  test "notification includes the inquiry details" do
    mail = LeadMailer.notification(build_lead)
    body = mail.body.encoded

    assert_match "Jane Developer", body
    assert_match "jane@example.com", body
    assert_match "Acme Inc.", body
    assert_match "We want help shipping agents.", body
  end

  test "an override address takes precedence over service routing" do
    ENV["LEADS_NOTIFICATION_ADDRESS"] = "inbox@activeagents.ai"
    mail = LeadMailer.notification(build_lead)
    assert_equal [ "inbox@activeagents.ai" ], mail.to
  ensure
    ENV.delete("LEADS_NOTIFICATION_ADDRESS")
  end

  test "confirmation goes to the lead" do
    mail = LeadMailer.confirmation(build_lead)

    assert_equal [ "jane@example.com" ], mail.to
    assert_match(/thanks for reaching out/i, mail.subject)
    assert_match "Jane Developer", mail.body.encoded
  end
end
