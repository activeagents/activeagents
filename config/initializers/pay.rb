Pay.setup do |config|
  config.business_name = "ActiveAgents"
  config.business_address = "San Francisco, CA"
  config.application_name = "ActiveAgent"
  config.support_email = "support@activeagents.ai"

  config.default_product_name = "default"
  config.default_plan_name = "default"

  config.automount_routes = true
  config.routes_path = "/pay"

  config.enabled_processors = [:stripe]
end

# Register custom webhook event subscribers for application-specific side effects.
# Pay handles core syncing (subscriptions, charges, payment methods) automatically.
# These add additional logging for observability.
Pay::Webhooks.configure do |events|
  events.subscribe "stripe.customer.subscription.created" do |event|
    Rails.logger.info "[Pay] Subscription created: #{event.data.object.id}"
  end

  events.subscribe "stripe.customer.subscription.updated" do |event|
    Rails.logger.info "[Pay] Subscription updated: #{event.data.object.id}, status: #{event.data.object.status}"
  end

  events.subscribe "stripe.customer.subscription.deleted" do |event|
    Rails.logger.info "[Pay] Subscription deleted: #{event.data.object.id}"
  end

  events.subscribe "stripe.charge.succeeded" do |event|
    Rails.logger.info "[Pay] Charge succeeded: #{event.data.object.id}"
  end

  events.subscribe "stripe.invoice.payment_failed" do |event|
    Rails.logger.info "[Pay] Payment failed: #{event.data.object.id}"
  end
end
