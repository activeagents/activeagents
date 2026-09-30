require "test_helper"
require_relative "../support/pilot_helpers"

class ProAccessTest < ActiveSupport::TestCase
  include PilotHelpers
  include ActiveJob::TestHelper

  setup do
    create_pilot_plans
    @admin = create_user(admin: true)
    @account = create_account(owner: create_user)
    @attributes = { account: @account, actor: @admin, source: "retainer_pilot", reason: "Retainer", review_on: Date.current + 30 }
  end

  test "only verified platform administrators can grant access" do
    assert_raises(ProAccess::NotAuthorized) { ProAccess.grant!(**@attributes.merge(actor: @account.owner)) }
    @admin.update!(email_verified: false)
    assert_raises(ProAccess::NotAuthorized) { ProAccess.grant!(**@attributes) }
    assert_equal 0, ProAccessGrant.count
  end

  test "grant retries and review extensions are idempotent and audited" do
    grant = ProAccess.grant!(**@attributes)
    2.times { ProAccess.grant!(**@attributes) }
    assert_equal 1, ProAccessGrant.count
    assert_equal [ "granted" ], grant.events.pluck(:action)
    ProAccess.grant!(**@attributes.merge(review_on: Date.current + 60))
    ProAccess.grant!(**@attributes.merge(review_on: Date.current + 60))
    assert_equal [ "granted", "updated" ], grant.events.order(:id).pluck(:action)
    assert_equal Date.current + 60, grant.reload.review_on
    assert_equal @admin.id, grant.events.last.actor_id
  end

  test "review dates do not expire access and grants use pro limits without paid status" do
    ProAccess.grant!(**@attributes.merge(review_on: Date.yesterday))
    assert_equal "pro", @account.current_plan.slug
    assert_equal 10_000, @account.effective_agent_runs_limit
    assert_equal 25_000, @account.effective_trace_limit
    assert_equal 14.days, @account.trace_retention
    assert_equal "complimentary_pilot", @account.access_source
    assert_not @account.subscribed?
    assert_not @account.paid_subscriber?
    assert_equal 0, Pay::Subscription.count
    other = create_account(owner: @account.owner)
    assert_equal "free", other.current_plan.slug
  end

  test "paid and trial subscriptions win over a grant and survive revocation" do
    enterprise = Plan.create!(name: "Enterprise", slug: "enterprise", price_cents: 200_000, stripe_monthly_price_id: "price_enterprise")
    grant = ProAccess.grant!(**@attributes)
    subscription = create_paid_subscription(@account, price: enterprise.stripe_monthly_price_id)
    assert_equal enterprise, @account.current_plan
    assert @account.paid_subscriber?
    ProAccess.revoke!(grant: grant, actor: @admin)
    assert_equal enterprise, @account.reload.current_plan
    assert_equal "active", subscription.reload.status
    subscription.update!(status: "trialing", trial_ends_at: 3.days.from_now)
    assert_equal "trial", @account.access_source
    assert_not @account.paid_subscriber?
    assert @account.subscribed?
  end

  test "expiration and revocation record once and preserve a retention grace period" do
    grant = ProAccess.grant!(**@attributes.merge(expires_at: 1.day.from_now))
    travel 2.days do
      2.times { ProAccess.expire!(grant) }
      assert_equal "free", @account.reload.current_plan.slug
      assert_equal 14.days, @account.trace_retention
      assert_equal 1, grant.events.where(action: "expired").count
    end
    travel 16.days do
      assert_equal 3.days, @account.reload.trace_retention
    end
    2.times { ProAccess.revoke!(grant: grant, actor: @admin) }
    assert_equal 1, grant.events.where(action: "revoked").count
  end

  test "notice retries send once after successful delivery" do
    grant = ProAccess.grant!(**@attributes)
    event = grant.events.first
    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      2.times { ProAccessNoticeJob.perform_now(event.id) }
    end
    assert event.reload.notified_at?
    assert_includes ActionMailer::Base.deliveries.last.body.decoded, "No automatic charge"
  end
end
