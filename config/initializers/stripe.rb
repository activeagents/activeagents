# Pay::Stripe.setup configures stripe-ruby in its to_prepare hook, using the
# environment before Rails credentials. Do not override it after initialization:
# that previously replaced the deployed key with a different credentials key.
Rails.application.config.after_initialize do
  if ENV["STRIPE_REQUIRE_TEST_MODE"] == "true"
    unless Stripe.api_key.to_s.match?(/\A[rs]k_test_/) && Stripe.api_key == Pay::Stripe.private_key
      raise "Staging billing requires matching Stripe and Pay test keys"
    end
  end
end
