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
