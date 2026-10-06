require "test_helper"

class StagingProBillingTest < ActiveSupport::TestCase
  class FakeStripe
    attr_accessor :livemode, :account_id, :fail_annual
    attr_reader :products, :prices, :writes, :reads

    def initialize
      @livemode = false
      @account_id = "acct_sandbox"
      @products = []
      @prices = []
      @writes = []
      @reads = []
    end

    def execute_request(method, path, params: {}, headers: {})
      if method == :post
        @writes << [ path, params, headers ]
        if path == "/v1/products"
          data = params.merge(active: true, livemode: false)
          @products << data
        else
          raise Stripe::APIConnectionError, "Simulated outage" if fail_annual && params.dig(:recurring, :interval) == "year"
          data = params.merge(id: "price_#{@prices.size + 1}", active: true, livemode: false,
            type: "recurring", billing_scheme: "per_unit",
            recurring: params[:recurring].merge(interval_count: 1, usage_type: "licensed"))
          @prices << data
        end
      else
        @reads << [ path, params ]
        data = case path
        when "/v1/balance" then { livemode: livemode }
        when "/v1/account" then { id: account_id }
        when "/v1/products" then { data: products.select { |product| product[:active] }, has_more: false }
        when "/v1/prices"
          selected = prices.select do |price|
            (!params[:product] || params[:product] == price[:product]) &&
              (!params[:lookup_keys] || params[:lookup_keys].include?(price[:lookup_key])) &&
              (!params[:active] || price[:active])
          end
          { data: selected, has_more: false }
        else
          (products + prices).find { |record| path.end_with?("/#{record[:id]}") } || raise("Unexpected request #{path}")
        end
      end
      [ Struct.new(:data).new(data), nil ]
    end
  end

  setup do
    @plan = Plan.create!(slug: "pro", name: "ActiveAgent.PRO", price_cents: 9900, annual_price_cents: 99_500, trial_days: 14)
    @stripe = FakeStripe.new
    @env = ENV.to_h.slice("STRIPE_PRO_MONTHLY_PRICE_ID", "STRIPE_PRO_ANNUAL_PRICE_ID")
    ENV.delete("STRIPE_PRO_MONTHLY_PRICE_ID")
    ENV.delete("STRIPE_PRO_ANNUAL_PRICE_ID")
  end

  teardown do
    %w[STRIPE_PRO_MONTHLY_PRICE_ID STRIPE_PRO_ANNUAL_PRICE_ID].each { |key| ENV[key] = @env[key] }
  end

  def provision(**overrides)
    StagingProBilling.new(**{
      expected_account_id: "acct_sandbox", api_key: "sk_test_example", pay_key: "sk_test_example",
      database_name: "activeagents_staging", client: @stripe
    }.merge(overrides)).configure!
  end

  test "creates only Pro and reuses prices on repeated setup and after database IDs are lost" do
    enterprise = Plan.create!(slug: "enterprise", name: "Enterprise", stripe_monthly_price_id: "price_unchanged")
    first = provision
    assert_equal first, provision
    @plan.update!(stripe_monthly_price_id: nil, stripe_annual_price_id: nil)
    assert_equal first, provision

    assert_equal 1, @stripe.products.size
    assert_equal [ 9900, 99_500 ], @stripe.prices.map { |price| price[:unit_amount] }
    assert_equal 3, @stripe.writes.size
    assert @stripe.writes.all? { |_, _, headers| headers["Idempotency-Key"].present? }
    assert_equal false, first[:livemode]
    assert_equal 14, @plan.reload.trial_days
    assert_equal "price_unchanged", enterprise.reload.stripe_monthly_price_id
  end

  test "rejects live keys, mismatched keys, missing account, and production before any API call" do
    [ { api_key: "sk_live_example" }, { pay_key: "sk_test_other" },
      { expected_account_id: nil }, { database_name: "activeagents_production" } ].each do |overrides|
      assert_raises(StagingProBilling::ConfigurationError) { provision(**overrides) }
    end
    assert_empty @stripe.reads
    assert_empty @stripe.writes
  end

  test "requires remote livemode false and the expected account before writes" do
    @stripe.livemode = true
    assert_raises(StagingProBilling::ConfigurationError) { provision }
    @stripe.livemode = false
    @stripe.account_id = "acct_other"
    assert_raises(StagingProBilling::ConfigurationError) { provision }
    assert_empty @stripe.writes
    assert_nil @plan.reload.stripe_monthly_price_id
  end

  test "refuses a changed trial or amount" do
    @plan.update!(trial_days: 0)
    assert_raises(StagingProBilling::ConfigurationError) { provision }
    @plan.update!(trial_days: 14, price_cents: 1)
    assert_raises(StagingProBilling::ConfigurationError) { provision }
    assert_empty @stripe.writes
  end

  test "validates both saved prices before creating or changing anything" do
    provision
    @stripe.writes.clear
    @stripe.prices.last[:unit_amount] = 100
    assert_raises(StagingProBilling::ConfigurationError) { provision }
    assert_empty @stripe.writes
  end

  test "refuses mismatched configured and saved prices" do
    provision
    @stripe.writes.clear
    ENV["STRIPE_PRO_MONTHLY_PRICE_ID"] = "price_other"
    assert_raises(StagingProBilling::ConfigurationError) { provision }
    assert_empty @stripe.writes
  end

  test "recovers a partial remote creation without duplicating products or monthly prices" do
    @stripe.fail_annual = true
    assert_raises(StagingProBilling::ConfigurationError) { provision }
    assert_nil @plan.reload.stripe_monthly_price_id
    @stripe.fail_annual = false
    provision
    assert_equal 1, @stripe.products.size
    assert_equal 2, @stripe.prices.size
    assert_equal "price_1", @plan.reload.stripe_monthly_price_id
  end

  test "reuses matching legacy Pro prices without lookup keys" do
    provision
    @stripe.prices.each { |price| price.delete(:lookup_key) }
    @plan.update!(stripe_monthly_price_id: nil, stripe_annual_price_id: nil)
    @stripe.writes.clear
    provision
    assert_empty @stripe.writes
    assert_equal "price_1", @plan.reload.stripe_monthly_price_id
  end

  test "refuses ambiguous legacy products instead of creating another" do
    @stripe.products.concat([ { id: "prod_1", active: true, metadata: { plan_slug: "pro" } },
      { id: "prod_2", active: true, metadata: { plan_slug: "pro" } } ])
    assert_raises(StagingProBilling::ConfigurationError) { provision }
    assert_empty @stripe.writes
  end

  test "seeds preserve provisioned prices when deployment variables are absent" do
    provision
    capture_io { load Rails.root.join("db/seeds.rb") }
    assert_equal "price_1", @plan.reload.stripe_monthly_price_id
    assert_equal "price_2", @plan.stripe_annual_price_id
  end
end
