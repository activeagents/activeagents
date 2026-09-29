# Serialize checkout creation per workspace and reuse its still-open session.
# Entitlements are supplied only by Pay's subscription lifecycle, never this URL.
class SubscriptionCheckout
  class AlreadySubscribed < StandardError; end

  def self.call(account:, plan:, price_id:, success_url:, cancel_url:)
    account.with_lock do
      raise AlreadySubscribed if account.billing_subscription
      return account.checkout_url if account.checkout_url? && account.checkout_expires_at&.future?

      customer = account.set_payment_processor(:stripe)
      checkout = customer.checkout(mode: "subscription",
        line_items: [ { price: price_id, quantity: 1 } ], success_url: success_url, cancel_url: cancel_url,
        subscription_data: plan.trial_days.positive? ? { trial_period_days: plan.trial_days } : {})
      account.update!(checkout_url: checkout.url, checkout_expires_at: Time.at(checkout.expires_at))
      checkout.url
    end
  end
end
