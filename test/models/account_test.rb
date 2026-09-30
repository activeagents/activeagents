# frozen_string_literal: true

require "test_helper"

class AccountTest < ActiveSupport::TestCase
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
end
