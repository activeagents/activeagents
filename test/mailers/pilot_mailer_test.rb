require "test_helper"
require_relative "../support/pilot_helpers"

class PilotMailerTest < ActionMailer::TestCase
  include PilotHelpers

  setup do
    @admin = create_user(admin: true)
    @invitation = WorkspaceInvitation.new(invited_by: @admin, email_address: "client@example.com", workspace_name: "Client Co",
      reason: "Retainer", review_on: Date.current + 90, source: "retainer_pilot")
  end

  test "invitation carries the accept link in a text part and an HTML part, with a reply-to" do
    mail = PilotMailer.invitation(@invitation, "the-token")

    assert_equal [ "client@example.com" ], mail.to
    assert_equal [ "hello@activeagents.ai" ], mail.reply_to
    assert_equal "Your Client Co Pro workspace invitation", mail.subject
    assert mail.multipart?
    accept_url = "/workspace_invitation?token=the-token"
    assert_includes mail.text_part.body.decoded, accept_url
    assert_includes mail.html_part.body.decoded, %(#{accept_url}")
    assert_includes mail.html_part.body.decoded, "Accept invitation"
  end
end
