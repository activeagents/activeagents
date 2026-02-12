namespace :stripe do
  desc "Create Stripe products and prices for ActiveAgent plans, then update local Plan records"
  task setup: :environment do
    require "stripe"

    unless Stripe.api_key.present?
      abort "Stripe API key not configured. Set STRIPE_PRIVATE_KEY or add stripe.private_key to Rails credentials."
    end

    puts "Creating Stripe products and prices..."

    # Pro Plan
    pro_product = Stripe::Product.create(
      name: "ActiveAgent.pro",
      description: "For small/medium teams & consultants — hosted dashboard, pro gems, 5 team seats"
    )

    pro_monthly_price = Stripe::Price.create(
      product: pro_product.id,
      unit_amount: 9_900,
      currency: "usd",
      recurring: { interval: "month" },
      lookup_key: "pro_monthly"
    )

    pro_annual_price = Stripe::Price.create(
      product: pro_product.id,
      unit_amount: 99_500,
      currency: "usd",
      recurring: { interval: "year" },
      lookup_key: "pro_annual"
    )

    puts "  Pro Monthly Price: #{pro_monthly_price.id}"
    puts "  Pro Annual Price:  #{pro_annual_price.id}"

    # Enterprise Plan — $269/mo per 100 agents (starting price)
    enterprise_product = Stripe::Product.create(
      name: "ActiveAgent.enterprise",
      description: "For large orgs & regulated industries — unlimited deployments, SOC 2/HIPAA, SSO/SAML, $269+/mo per 100 agents"
    )

    enterprise_monthly_price = Stripe::Price.create(
      product: enterprise_product.id,
      unit_amount: 26_900,
      currency: "usd",
      recurring: { interval: "month" },
      lookup_key: "enterprise_monthly"
    )

    puts "  Enterprise Monthly Price: #{enterprise_monthly_price.id}"

    # Update local Plan records with Stripe Price IDs
    pro_plan = Plan.find_by(slug: "pro")
    if pro_plan
      pro_plan.update!(
        stripe_monthly_price_id: pro_monthly_price.id,
        stripe_annual_price_id: pro_annual_price.id
      )
      puts "  Updated Pro plan with Stripe Price IDs"
    else
      puts "  WARNING: Pro plan not found in database. Run `rails db:seed` first."
    end

    enterprise_plan = Plan.find_by(slug: "enterprise")
    if enterprise_plan
      enterprise_plan.update!(
        stripe_monthly_price_id: enterprise_monthly_price.id
      )
      puts "  Updated Enterprise plan with Stripe Price IDs"
    else
      puts "  WARNING: Enterprise plan not found in database. Run `rails db:seed` first."
    end

    puts "\nDone! Stripe products and prices created successfully."
    puts "\nNext steps:"
    puts "  1. Configure your Stripe webhook endpoint to: https://yourdomain.com/pay/webhooks/stripe"
    puts "  2. Set the webhook signing secret in STRIPE_SIGNING_SECRET or Rails credentials"
    puts "  3. For local development, run: stripe listen --forward-to localhost:3000/pay/webhooks/stripe"
  end
end
