# Stripe configuration
# Pay gem reads these environment variables automatically:
#   STRIPE_PRIVATE_KEY  - Stripe secret key
#   STRIPE_PUBLIC_KEY   - Stripe publishable key
#   STRIPE_SIGNING_SECRET - Webhook signing secret
#
# Alternatively, store them in Rails credentials:
#   rails credentials:edit
#   stripe:
#     private_key: sk_test_...
#     public_key: pk_test_...
#     signing_secret: whsec_...

Rails.application.config.after_initialize do
  stripe_key = Rails.application.credentials.dig(:stripe, :private_key) || ENV["STRIPE_PRIVATE_KEY"]

  if stripe_key.present? && !defined?(Stripe).nil?
    Stripe.api_key = stripe_key
  end
end
