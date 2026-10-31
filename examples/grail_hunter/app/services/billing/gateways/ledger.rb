module Billing
  module Gateways
    # Books a charge as settled. No money moves; the ledger is the product's
    # record of what it is owed. See Billing for where a card gateway plugs in.
    class Ledger
      def charge!(user, amount_cents:, kind:, description:, discovery_run: nil, period_start: nil, period_end: nil)
        user.charges.create!(
          amount_cents: amount_cents,
          currency: "USD",
          kind: kind,
          description: description,
          discovery_run: discovery_run,
          period_start: period_start,
          period_end: period_end,
          status: "settled"
        )
      end
    end
  end
end
