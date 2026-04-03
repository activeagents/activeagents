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
