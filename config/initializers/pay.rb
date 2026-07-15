Pay.setup do |config|
  config.business_name = "Active Agents"
  config.business_address = ""
  config.application_name = "Active Agents"
  config.support_email = "support@activeagents.ai"

  config.default_product_name = "Active Agents"
  config.default_plan_name = "Pro"

  config.automount_routes = true
  config.routes_path = "/pay"
end

# Map STRIPE_WEBHOOK_SECRET to what Pay gem expects
# Pay gem looks for STRIPE_SIGNING_SECRET or credentials[:stripe][:signing_secret]
ENV["STRIPE_SIGNING_SECRET"] ||= ENV["STRIPE_WEBHOOK_SECRET"] if ENV["STRIPE_WEBHOOK_SECRET"]

# Same bridging for the API key: deploys (see terraform cloud-run env) provide
# STRIPE_API_KEY, but Pay authenticates from STRIPE_PRIVATE_KEY or
# credentials[:stripe][:private_key]
ENV["STRIPE_PRIVATE_KEY"] ||= ENV["STRIPE_API_KEY"] if ENV["STRIPE_API_KEY"]
