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
report[:key_accounts] = {}
{ global: Stripe.api_key, pay: Pay::Stripe.private_key, environment: ENV["STRIPE_API_KEY"] }.each do |source, key|
  next unless key_mode.call(key) == "test"
  begin
    client = Stripe::StripeClient.new(key)
    read = ->(path, params = {}) { client.execute_request(:get, path, params: params).first.data }
    balance = read.call("/v1/balance")
    unless balance[:livemode] == false
      report[:key_accounts][source] = { error: "Stripe did not report livemode=false" }
      next
    end
    account = read.call("/v1/account")
    report[:key_accounts][source] = { stripe_account: account[:id], livemode: false }
    next unless source == :environment
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
  rescue Stripe::StripeError => error
    report[:key_accounts][source] = { error: error.class.name, http_status: error.http_status }
  end
end
puts "STAGING_BILLING_DIAGNOSTICS #{JSON.generate(report)}"
