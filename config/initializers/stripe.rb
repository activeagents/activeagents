Rails.application.config.after_initialize do
  if defined?(Stripe)
    Stripe.api_key = Rails.application.credentials.dig(:stripe, :private_key) || ENV["STRIPE_API_KEY"]
  end
end
