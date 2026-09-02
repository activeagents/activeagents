# frozen_string_literal: true

require "test_helper"

# The channel streams full run output, so it enforces the same caller scoping
# as Api::SandboxesController: an observed session_id must not be enough to
# stream another owner's sandbox.
class SandboxChannelTest < ActionCable::Channel::TestCase
  setup do
    @owner = create_user(email: "channel-owner-#{SecureRandom.hex(4)}@example.com")
    @owner_sandbox = SandboxSession.create!(sandbox_type: "playwright_mcp", status: :ready, user: @owner)
    @anonymous_sandbox = SandboxSession.create!(sandbox_type: "playwright_mcp", status: :ready, user: nil)
  end

  test "rejects a subscription with no session_id" do
    stub_connection current_user: @owner, anonymous_id: nil

    subscribe

    assert subscription.rejected?
  end

  test "streams the caller's own sandbox" do
    stub_connection current_user: @owner, anonymous_id: nil

    subscribe session_id: @owner_sandbox.session_id

    assert subscription.confirmed?
    assert_has_stream "sandbox_#{@owner_sandbox.session_id}"
  end

  test "rejects another user's subscription to an owned sandbox" do
    intruder = create_user(email: "channel-intruder-#{SecureRandom.hex(4)}@example.com")
    stub_connection current_user: intruder, anonymous_id: nil

    subscribe session_id: @owner_sandbox.session_id

    assert subscription.rejected?
  end

  test "rejects an anonymous subscription to an owned sandbox" do
    stub_connection current_user: nil, anonymous_id: SecureRandom.uuid

    subscribe session_id: @owner_sandbox.session_id

    assert subscription.rejected?
  end

  test "streams an anonymous demo sandbox for an anonymous caller" do
    stub_connection current_user: nil, anonymous_id: SecureRandom.uuid

    subscribe session_id: @anonymous_sandbox.session_id

    assert subscription.confirmed?
    assert_has_stream "sandbox_#{@anonymous_sandbox.session_id}"
  end
end
