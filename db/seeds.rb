# Pricing plans
# Stripe Price IDs are placeholders — update with real IDs after running `rails stripe:setup`
# or creating products/prices manually in the Stripe Dashboard.

Plan.find_or_create_by!(slug: "free") do |plan|
  plan.name = "ActiveAgent.dev"
  plan.price_cents = 0
  plan.annual_price_cents = 0
  plan.stripe_monthly_price_id = nil
  plan.stripe_annual_price_id = nil
  plan.trial_days = 0
  plan.included_seats = 1
  plan.included_workspaces = 0
  plan.features = {
    hosted_dashboard: false,
    cost_analytics: false,
    ab_testing: false,
    anomaly_detection: false,
    sso: false,
    soc2_hipaa: false,
    private_vpc: false,
    dedicated_slack: false,
    email_sla_hours: nil,
    max_deployments: 0,
    max_executions: 0,
    max_traces: 0,
    trace_retention_days: 0,
    reasonable_reasons_gems: false,
    generative_ui: false,
    parallel_tasks: false,
    hitl_generative_ui: false,
    agentic_workflows: false
  }
end

Plan.find_or_create_by!(slug: "pro") do |plan|
  plan.name = "ActiveAgent.pro"
  plan.price_cents = 9_900           # $99/month
  plan.annual_price_cents = 99_500   # $995/year
  plan.stripe_monthly_price_id = ENV.fetch("STRIPE_PRO_MONTHLY_PRICE_ID", "price_pro_monthly_placeholder")
  plan.stripe_annual_price_id = ENV.fetch("STRIPE_PRO_ANNUAL_PRICE_ID", "price_pro_annual_placeholder")
  plan.trial_days = 14
  plan.included_seats = 5
  plan.included_workspaces = 1
  plan.features = {
    hosted_dashboard: true,
    cost_analytics: true,
    ab_testing: true,
    anomaly_detection: false,
    sso: false,
    soc2_hipaa: false,
    private_vpc: false,
    dedicated_slack: false,
    email_sla_hours: 48,
    max_deployments: 3,
    max_executions: 10_000,
    max_traces: 25_000,
    trace_retention_days: 14,
    reasonable_reasons_gems: true,
    generative_ui: true,
    parallel_tasks: true,
    hitl_generative_ui: true,
    agentic_workflows: true
  }
end

Plan.find_or_create_by!(slug: "enterprise") do |plan|
  plan.name = "ActiveAgent.enterprise"
  plan.price_cents = 26_900             # $269/month per 100 agents (starting)
  plan.annual_price_cents = 0           # Custom annual pricing, contact sales
  plan.stripe_monthly_price_id = ENV.fetch("STRIPE_ENTERPRISE_MONTHLY_PRICE_ID", "price_enterprise_monthly_placeholder")
  plan.stripe_annual_price_id = nil     # Enterprise annual is custom/contact sales
  plan.trial_days = 0
  plan.included_seats = -1              # -1 means unlimited
  plan.included_workspaces = -1
  plan.features = {
    hosted_dashboard: true,
    cost_analytics: true,
    ab_testing: true,
    anomaly_detection: true,
    sso: true,
    soc2_hipaa: true,
    private_vpc: true,
    dedicated_slack: true,
    email_sla_hours: 4,
    max_deployments: -1,
    max_executions: -1,
    max_traces: 500_000,
    trace_retention_days: 400,
    reasonable_reasons_gems: true,
    generative_ui: true,
    parallel_tasks: true,
    hitl_generative_ui: true,
    agentic_workflows: true,
    unlimited_custom_evaluators: true,
    appliance_license_available: true
  }
end

puts "Seeded #{Plan.count} plans"
