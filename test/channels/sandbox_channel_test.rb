# frozen_string_literal: true

require "test_helper"

# The channel streams full run output, so it enforces the same caller scoping
# as Api::SandboxesController: an observed session_id must not be enough to
# stream another owner's sandbox.
class SandboxChannelTest < ActionCable::Channel::TestCase
  setup do
    @owner = create_user(email: "channel-owner-#{SecureRandom.hex(4)}@example.com")
    @account = create_account(owner: @owner)
    @owner_sandbox = SandboxSession.create!(sandbox_type: "playwright_mcp", status: :ready, user: @owner, account: @account)
    @anonymous_sandbox = SandboxSession.create!(sandbox_type: "playwright_mcp", status: :ready, user: nil)
  end

  test "rejects a subscription with no session_id" do
    stub_connection current_user: @owner, current_account: @account, anonymous_id: nil

    subscribe

    assert subscription.rejected?
  end

  test "streams the caller's own sandbox" do
    stub_connection current_user: @owner, current_account: @account, anonymous_id: nil

    subscribe session_id: @owner_sandbox.session_id

    assert subscription.confirmed?
    assert_has_stream "sandbox_#{@owner_sandbox.session_id}"
  end

  test "rejects another user's subscription to an owned sandbox" do
    intruder = create_user(email: "channel-intruder-#{SecureRandom.hex(4)}@example.com")
    stub_connection current_user: intruder, current_account: create_account(owner: intruder), anonymous_id: nil

    subscribe session_id: @owner_sandbox.session_id

    assert subscription.rejected?
  end

  test "rejects a sandbox in a different workspace owned by the same user" do
    second = create_account(owner: @owner)
    stub_connection current_user: @owner, current_account: second, anonymous_id: nil
    subscribe session_id: @owner_sandbox.session_id
    assert subscription.rejected?
  end

  test "unverified owners cannot subscribe to private sandbox output" do
    @owner.update!(email_verified: false)
    stub_connection current_user: @owner, current_account: @account, anonymous_id: nil
    subscribe session_id: @owner_sandbox.session_id
    assert subscription.rejected?
  end

  test "rejects an anonymous subscription to an owned sandbox" do
    stub_connection current_user: nil, current_account: nil, anonymous_id: SecureRandom.uuid

    subscribe session_id: @owner_sandbox.session_id

    assert subscription.rejected?
  end

  test "streams an anonymous demo sandbox for an anonymous caller" do
    stub_connection current_user: nil, current_account: nil, anonymous_id: SecureRandom.uuid

    subscribe session_id: @anonymous_sandbox.session_id

    assert subscription.confirmed?
    assert_has_stream "sandbox_#{@anonymous_sandbox.session_id}"
  end
end
