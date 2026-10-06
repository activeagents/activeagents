# Pro catalog provisioning for staging only. This never creates subscriptions.
# Pay 7.3 pins stripe-ruby 12, whose instance request API is execute_request.
class StagingProBilling
  class ConfigurationError < StandardError; end

  PRODUCT_ID = "activeagents_staging_pro".freeze
  PRICES = {
    monthly: { amount: 9900, interval: "month", field: :stripe_monthly_price_id },
    annual: { amount: 99_500, interval: "year", field: :stripe_annual_price_id }
  }.freeze

  def initialize(expected_account_id:, api_key: Stripe.api_key, pay_key: Pay::Stripe.private_key,
    database_name: ActiveRecord::Base.connection_db_config.database, client: nil)
    check!(database_name == "activeagents_staging", "This task is restricted to the staging database")
    check!(api_key.to_s.match?(/\A[rs]k_test_/), "A Stripe test key is required")
    check!(api_key == pay_key, "Stripe and Pay must use the same test key")
    check!(expected_account_id.to_s.match?(/\Aacct_[A-Za-z0-9]+\z/), "STRIPE_EXPECTED_ACCOUNT_ID is required")
    @expected_account_id = expected_account_id
    @client = client || Stripe::StripeClient.new(api_key)
  end

  def configure!
    check!(request(:get, "/v1/balance")[:livemode] == false, "Stripe must report livemode=false")
    account = request(:get, "/v1/account")
    check!(account[:id] == @expected_account_id, "Stripe account does not match STRIPE_EXPECTED_ACCOUNT_ID")

    plan = Plan.find_by!(slug: "pro")
    plan.with_lock do
      check!(plan.active? && plan.price_cents == 9900 && plan.annual_price_cents == 99_500 && plan.trial_days == 14,
        "Pro must be active with $99/month, $995/year, and a 14-day trial")

      # Validate every configured price before creating anything remotely.
      prices = PRICES.to_h do |interval, spec|
        configured = ENV["STRIPE_PRO_#{interval.to_s.upcase}_PRICE_ID"].presence
        saved = plan.public_send(spec[:field]).presence
        check!(!configured || !saved || configured == saved, "Configured and saved #{interval} prices disagree")
        id = configured || saved
        price = id ? request(:get, "/v1/prices/#{validated_id!(id, 'price')}") : lookup_price(interval)
        validate_price!(price, spec) if price
        [ interval, price ]
      end
      product_ids = prices.values.compact.map { |price| price.fetch(:product) }.uniq
      check!(product_ids.size <= 1, "Both Pro prices must belong to the same product")
      product = product_ids.any? ? request(:get, "/v1/products/#{validated_id!(product_ids.first, 'prod')}") : find_product
      validate_product!(product) if product

      # Reuse matching legacy prices too; refuse ambiguous duplicates.
      if product
        existing = list("/v1/prices", product: product.fetch(:id), active: true)
        PRICES.each do |interval, spec|
          next if prices[interval]
          matches = existing.select { |price| price_matches?(price, spec) }
          check!(matches.size <= 1, "Multiple matching #{interval} prices exist; configure an explicit price ID")
          prices[interval] = matches.first
        end
      end

      product ||= request(:post, "/v1/products", {
        id: PRODUCT_ID, name: "ActiveAgent.PRO", metadata: { plan_slug: "pro", environment: "staging" }
      }, idempotency_key: "#{PRODUCT_ID}-v1")
      validate_product!(product)

      PRICES.each do |interval, spec|
        prices[interval] ||= request(:post, "/v1/prices", {
          product: product.fetch(:id), unit_amount: spec[:amount], currency: "usd",
          recurring: { interval: spec[:interval] }, lookup_key: lookup_key(interval),
          metadata: { plan_slug: "pro", environment: "staging" }
        }, idempotency_key: lookup_key(interval))
        validate_price!(prices.fetch(interval), spec)
        check!(prices.fetch(interval)[:product] == product[:id], "Price product mismatch")
      end

      attributes = PRICES.to_h { |interval, spec| [ spec[:field], prices.fetch(interval).fetch(:id) ] }
      plan.update!(attributes) unless attributes.all? { |field, value| plan.public_send(field) == value }
      { stripe_account: account.fetch(:id), livemode: false, plan: "pro", trial_days: plan.trial_days }.merge(attributes)
    end
  end

  private

  def request(method, path, params = {}, idempotency_key: nil)
    headers = idempotency_key ? { "Idempotency-Key" => idempotency_key } : {}
    @client.execute_request(method, path, params: params, headers: headers).first.data
  rescue Stripe::StripeError => error
    # Error bodies can contain request data; keep credentials out of job logs.
    raise ConfigurationError, "Stripe request failed (#{error.class.name}, HTTP #{error.http_status})"
  end

  def list(path, params = {})
    records = []
    loop do
      page = request(:get, path, params.merge(limit: 100))
      records.concat(page.fetch(:data))
      return records unless page[:has_more]
      params = params.merge(starting_after: page.fetch(:data).last.fetch(:id))
    end
  end

  def find_product
    products = list("/v1/products", active: true).select { |product| product.dig(:metadata, :plan_slug) == "pro" }
    check!(products.size <= 1, "Multiple Pro products exist; configure explicit price IDs")
    products.first
  end

  def lookup_price(interval)
    matches = list("/v1/prices", lookup_keys: [ lookup_key(interval) ])
    check!(matches.size <= 1, "Multiple prices have the staging Pro lookup key")
    matches.first
  end

  def lookup_key(interval)
    "#{PRODUCT_ID}_#{interval}_usd_#{PRICES.fetch(interval)[:amount]}_v1"
  end

  def validate_product!(product)
    check!(product[:livemode] == false && product[:active] == true && product.dig(:metadata, :plan_slug) == "pro",
      "Product must be an active test-mode Pro product")
  end

  def validate_price!(price, spec)
    check!(price_matches?(price, spec), "Price must be active test-mode USD #{spec[:amount]} per #{spec[:interval]}")
  end

  def price_matches?(price, spec)
    price[:livemode] == false && price[:active] == true && price[:currency] == "usd" &&
      price[:unit_amount] == spec[:amount] && price[:type] == "recurring" &&
      price[:billing_scheme] == "per_unit" && price[:transform_quantity].nil? &&
      price.dig(:recurring, :interval) == spec[:interval] &&
      price.dig(:recurring, :interval_count) == 1 && price.dig(:recurring, :usage_type) == "licensed"
  end

  def validated_id!(id, type)
    valid = id.to_s.match?(/\A#{type}_[A-Za-z0-9]+\z/) || (type == "prod" && id == PRODUCT_ID)
    check!(valid, "Invalid #{type} ID")
    id
  end

  def check!(condition, message)
    raise ConfigurationError, message unless condition
  end
end
