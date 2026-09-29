require "test_helper"
require_relative "../support/pilot_helpers"

class PilotAdministrationTest < ActionDispatch::IntegrationTest
  include PilotHelpers
  include ActiveJob::TestHelper

  setup do
    create_pilot_plans
    @admin = create_user(admin: true)
  end

  test "admin prepares a normalized draft without sending and sees accurate pilot reporting" do
    sign_in_as(@admin)
    assert_no_enqueued_jobs only: WorkspaceInvitationDeliveryJob do
      post "/admin/pilot_invitations", params: { invitation: { email_address: " CLIENT@EXAMPLE.COM ", workspace_name: "Client", reason: "Retainer", review_on: Date.current + 30 } }
      assert_redirected_to "/admin/pilots"
    end
    invitation = WorkspaceInvitation.last
    assert_equal "client@example.com", invitation.email_address
    assert_equal "draft", invitation.status
    assert_enqueued_with(job: WorkspaceInvitationDeliveryJob) do
      post "/admin/pilot_invitations/#{invitation.id}/deliver"
    end
    account = create_account(owner: create_user)
    ProAccess.grant!(account: account, actor: @admin, source: "retainer_pilot", reason: "Retainer", review_on: Date.current + 30)
    get "/admin/pilots"
    assert_response :success
    assert_includes response.body, "Complimentary pilot"
    assert_includes response.body, "Paying subscriber: <strong>No</strong>"
    assert_includes response.body, "Not yet"
  end

  test "nonadmins cannot view prepare send revoke or grant" do
    invitation = prepare_invitation(admin: @admin)
    user = create_user
    account = create_account(owner: user)
    sign_in_as(user)
    get "/admin/pilots"
    assert_redirected_to "/"
    assert_no_difference [ "WorkspaceInvitation.count", "ProAccessGrant.count" ] do
      post "/admin/pilot_invitations", params: { invitation: { email_address: "x@example.com" } }
      assert_redirected_to "/"
      post "/admin/pilot_invitations/#{invitation.id}/deliver"
      assert_redirected_to "/"
      post "/admin/pilot_invitations/#{invitation.id}/revoke"
      assert_redirected_to "/"
      post "/admin/pro_access_grants", params: { account_id: account.id, grant: { source: "retainer_pilot" } }
      assert_redirected_to "/"
    end
    assert_equal "draft", invitation.reload.status
  end

  test "delivery retries are versioned failures are visible and resending invalidates the old link" do
    invitation = prepare_invitation(admin: @admin)
    first_token = deliver_invitation(invitation)
    first_version = invitation.reload.delivery_version
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      WorkspaceInvitationDeliveryJob.perform_now(invitation.id, first_version)
    end
    invitation.queue_delivery!(actor: @admin)
    assert_nil WorkspaceInvitation.for_token(first_token)
    with_method(PilotMailer, :invitation, ->(*) { raise IOError, "Synthetic delivery failure" }) do
      WorkspaceInvitationDeliveryJob.perform_now(invitation.id, invitation.reload.delivery_version)
    end
    assert_equal "delivery_failed", invitation.reload.status
    assert_equal "IOError", invitation.delivery_error
    assert_nil invitation.token_digest
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      WorkspaceInvitationDeliveryJob.perform_now(invitation.id, first_version)
    end
    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      token = deliver_invitation(invitation)
      assert WorkspaceInvitation.for_token(token).usable?
    end
  end

  test "email bodies containing invitation tokens are redacted from mail instrumentation" do
    invitation = prepare_invitation(admin: @admin)
    payloads = []
    subscriber = ->(*arguments) { payloads << arguments.last }
    ActiveSupport::Notifications.subscribed(subscriber, "deliver.action_mailer") do
      token = deliver_invitation(invitation)
      assert_not_includes payloads.last[:mail], token
      assert_includes ActionMailer::Base.deliveries.last.body.decoded, token
    end
  end
end
