namespace :stripe do
  desc "Create Stripe products and prices, then update local Plan records"
  task setup: :environment do
    unless Stripe.api_key.present?
      abort "STRIPE_PRIVATE_KEY is not set. Please set it in your environment or credentials."
    end

    plans_config = [
      {
        slug: "pro",
        product_name: "ActiveAgent.PRO",
        monthly_price: 9900,
        annual_price: 99_500,
        currency: "usd"
      },
      {
        slug: "enterprise",
        product_name: "ActiveAgent Enterprise",
        monthly_price: 26_900,
        annual_price: 269_000,
        currency: "usd"
      }
    ]

    plans_config.each do |config|
      plan = Plan.find_by!(slug: config[:slug])

      # Check if we already have Stripe IDs stored
      if plan.stripe_monthly_price_id.present? && plan.stripe_annual_price_id.present?
        puts "Plan '#{config[:slug]}' already has Stripe price IDs. Skipping creation."
        puts "  Monthly: #{plan.stripe_monthly_price_id}"
        puts "  Annual: #{plan.stripe_annual_price_id}"
        puts ""
        next
      end

      # Look for existing Stripe product with this plan_slug metadata
      existing_products = Stripe::Product.search(
        query: "metadata['plan_slug']:'#{config[:slug]}' AND active:'true'"
      ).data

      product = if existing_products.any?
        existing_products.first
      else
        # Create new Stripe product
        Stripe::Product.create(
          name: config[:product_name],
          metadata: { plan_slug: config[:slug] }
        )
      end
      puts "Using Stripe product: #{product.name} (#{product.id})"

      # Look for existing prices for this product
      existing_prices = Stripe::Price.list(product: product.id, active: true).data
      monthly_price = existing_prices.find { |p| p.recurring&.interval == "month" }
      annual_price = existing_prices.find { |p| p.recurring&.interval == "year" }

      # Create monthly price if it doesn't exist
      unless monthly_price
        monthly_price = Stripe::Price.create(
          product: product.id,
          unit_amount: config[:monthly_price],
          currency: config[:currency],
          recurring: { interval: "month" },
          metadata: { plan_slug: config[:slug], interval: "monthly" }
        )
      end
      puts "  Monthly price: $#{config[:monthly_price] / 100.0}/mo (#{monthly_price.id})"

      # Create annual price if it doesn't exist
      unless annual_price
        annual_price = Stripe::Price.create(
          product: product.id,
          unit_amount: config[:annual_price],
          currency: config[:currency],
          recurring: { interval: "year" },
          metadata: { plan_slug: config[:slug], interval: "annual" }
        )
      end
      puts "  Annual price: $#{config[:annual_price] / 100.0}/yr (#{annual_price.id})"

      # Update local plan record
      plan.update!(
        stripe_monthly_price_id: monthly_price.id,
        stripe_annual_price_id: annual_price.id
      )
      puts "  Updated local plan record with Stripe price IDs"
      puts ""
    end

    puts "Stripe setup complete!"
    puts ""
    puts "Next steps:"
    puts "1. Configure webhooks in Stripe Dashboard -> Developers -> Webhooks"
    puts "   Endpoint URL: https://your-domain.com/pay/webhooks/stripe"
    puts "   Events to listen for:"
    puts "     - customer.subscription.created"
    puts "     - customer.subscription.updated"
    puts "     - customer.subscription.deleted"
    puts "     - customer.subscription.trial_will_end"
    puts "     - charge.succeeded"
    puts "     - charge.refunded"
    puts "     - payment_method.attached"
    puts "     - payment_method.updated"
    puts "2. Set the STRIPE_SIGNING_SECRET environment variable with the webhook signing secret"
  end
end
