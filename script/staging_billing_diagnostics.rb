# Run with bin/rails runner in the existing staging Cloud Run job.
# Never print credentials, customer details, webhook payloads, or signing secrets.
require "json"

abort "Refusing billing diagnostics outside the staging database" unless
  ActiveRecord::Base.connection_db_config.database == "activeagents_staging"

key_mode = ->(key) do
  case key.to_s
  when /\A[rs]k_test_/ then "test"
  when /\A[rs]k_live_/ then "live"
  when "" then "missing"
  else "unrecognized"
  end
end

report = {
  database: ActiveRecord::Base.connection_db_config.database,
  stripe_key_mode: key_mode.call(Stripe.api_key),
  pay_key_mode: key_mode.call(Pay::Stripe.private_key),
  environment_key_mode: key_mode.call(ENV["STRIPE_API_KEY"]),
  effective_keys_match: Stripe.api_key == Pay::Stripe.private_key,
  webhook_secret_present: Pay::Stripe.signing_secret.present?,
  webhook_secret_matches_environment: Pay::Stripe.signing_secret == ENV["STRIPE_WEBHOOK_SECRET"],
  receive_test_events: Pay::Stripe.webhook_receive_test_events,
  pro: Plan.find_by!(slug: "pro").attributes.slice(
    "id", "slug", "price_cents", "annual_price_cents", "trial_days",
    "stripe_monthly_price_id", "stripe_annual_price_id"
  )
}

puts "STAGING_BILLING_DIAGNOSTICS #{JSON.generate(report)}"
abort "Staging billing must use matching test keys; no Stripe request was made" unless
  report[:stripe_key_mode] == "test" && report[:effective_keys_match]

client = Stripe::StripeClient.new(Stripe.api_key)
read = ->(path, params = {}) { client.execute_request(:get, path, params: params).first.data }
balance = read.call("/v1/balance")
abort "Stripe reported livemode=true; stopping" unless balance[:livemode] == false

account = read.call("/v1/account")
report[:stripe_account] = account[:id]
report[:livemode] = balance[:livemode]
report[:staging_webhooks] = []
params = { limit: 100 }
loop do
  page = read.call("/v1/webhook_endpoints", params)
  page[:data].each do |endpoint|
    next unless endpoint[:url] == "https://staging.activeagents.ai/pay/webhooks/stripe"
    report[:staging_webhooks] << endpoint.slice(:id, :url, :livemode, :status, :enabled_events, :api_version)
  end
  break unless page[:has_more]
  params[:starting_after] = page[:data].last.fetch(:id)
end
puts "STAGING_BILLING_DIAGNOSTICS #{JSON.generate(report)}"
