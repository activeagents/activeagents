# frozen_string_literal: true

require "test_helper"
require_relative "../support/teammate_helpers"

class AccountTest < ActiveSupport::TestCase
  include TeammateHelpers

  setup do
    @account = create_account(owner: create_user)
  end

  test "::authenticate_api_token resolves a generated API key and records its use" do
    api_key = @account.api_keys.create!(name: "ingest")

    assert_equal @account, Account.authenticate_api_token(api_key.token)
    assert api_key.reload.last_used_at.present?, "expected the key's use to be recorded"
  end

  test "::authenticate_api_token resolves the account's telemetry key" do
    assert_equal @account, Account.authenticate_api_token(@account.telemetry_api_key)
  end

  test "::authenticate_api_token returns nil for a blank or unknown token" do
    assert_nil Account.authenticate_api_token("")
    assert_nil Account.authenticate_api_token("aa_unknown")
  end

  test "#current_plan reads a fake_processor comp as the plan with that slug" do
    Plan.create!(name: "Enterprise", slug: "enterprise", price_cents: 200_000)
    @account.set_payment_processor(:fake_processor, allow_fake: true)
    @account.payment_processor.subscribe(plan: "enterprise")

    assert_equal "enterprise", @account.reload.current_plan.slug
    assert_equal(-1, @account.effective_trace_limit, "an enterprise comp lifts the trace quota")
  end

  test "#seat_limit comes from the plan's included seats" do
    create_seat_plans

    assert_equal 1, @account.seat_limit, "Free includes one seat"
    assert_equal 3, team_account(plan: "pro").seat_limit
    assert_equal(-1, team_account(plan: "enterprise").seat_limit)
  end

  test "#seats_in_use counts members and invitations still holding a seat" do
    create_seat_plans
    account = team_account(plan: "pro")
    add_member(account)
    invitation = WorkspaceMembers.new(account, actor: account.owner).invite!(email_address: "pending@example.com", role: "member")

    assert_equal 3, account.seats_in_use
    assert_equal 2, account.seats_in_use(except: invitation)
    assert_not account.seat_available?
    assert account.seat_available?(except: invitation)

    invitation.update!(token_expires_at: 1.minute.ago)
    assert_equal 2, account.seats_in_use, "an expired invitation frees its seat"
  end

  test "#seat_available? is always true on an unlimited plan" do
    create_seat_plans
    account = team_account(plan: "enterprise")
    5.times { add_member(account) }

    assert account.seat_available?
  end

  test "destroying a workspace deletes its teammate invitations" do
    create_seat_plans
    account = team_account(plan: "pro")
    WorkspaceMembers.new(account, actor: account.owner).invite!(email_address: "pending@example.com", role: "member")

    assert_difference "WorkspaceInvitation.count", -1 do
      account.destroy!
    end
  end
end
