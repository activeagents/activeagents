# How the product gets paid.
#
# Two ways, both ending in Charge rows the account page itemises:
#
#   * Pay as you go: a fee per discovery run, at the rate of the plan the
#     collector is on when the run is created (Hunt#run_now! fixes it on the
#     run). Billing.record_run_fee! books it when the run completes.
#   * A subscription: a monthly fee that lowers the per-run fee and unlocks
#     more frequent scheduled hunts. Billing.subscribe! books the first month
#     and moves the account to the plan.
#
# Payment collection sits behind Billing.gateway. The shipped gateway is a
# ledger: it settles charges on the books and nothing else, which is what a
# demo and a test suite want. A card gateway (Stripe, say) implements the
# same one method, charges the customer's saved payment method and settles
# or voids the row from its webhook.
module Billing
  class Error < StandardError; end

  class << self
    attr_writer :gateway

    def gateway
      @gateway ||= Gateways::Ledger.new
    end

    # @return [User]
    def subscribe!(user, plan)
      plan = Plan.find(plan) unless plan.is_a?(Plan)
      raise Error, "#{plan.name} is not a subscription plan" unless plan.subscription?
      return user if user.plan == plan

      user.transaction do
        gateway.charge!(
          user,
          amount_cents: plan.monthly_cents,
          kind: "subscription",
          description: "#{plan.name} plan, one month",
          period_start: Date.current,
          period_end: Date.current + 1.month
        )
        user.update!(plan_key: plan.key, subscribed_at: Time.current, subscription_renews_at: 1.month.from_now)
      end
      user
    end

    # Back to the default plan. Hunts on a schedule the default plan does
    # not include are slowed to its fastest one rather than stopped.
    def cancel!(user)
      default = Plan.default

      user.transaction do
        user.update!(plan_key: default.key, subscribed_at: nil, subscription_renews_at: nil)
        user.hunts.find_each do |hunt|
          next if default.allows_frequency?(hunt.frequency)

          hunt.update!(frequency: default.fastest_frequency)
        end
      end
      user
    end

    # Books the fee a completed run costs. Idempotent per run, and nothing
    # is booked for a run on a plan with no per-run fee.
    # @return [Charge, nil]
    def record_run_fee!(run)
      return nil if run.fee_cents.zero? || run.charge.present?

      gateway.charge!(
        run.user,
        amount_cents: run.fee_cents,
        kind: "run_fee",
        description: "Hunt: #{run.hunt.title}",
        discovery_run: run
      )
    end
  end
end
