# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Agent Templates
puts "Seeding agent templates..."
AgentTemplate.seed_defaults!
puts "Created #{AgentTemplate.count} agent templates"

# Skip user/agent seeding in production
unless Rails.env.production?
  puts "\nSeeding demo data..."

  # Create demo user
  demo_user = User.find_or_create_by!(email_address: "demo@example.com") do |user|
    user.password = "password123"
    user.password_confirmation = "password123"
  end
  puts "Created demo user: #{demo_user.email_address}"

  # Create account for demo user if not exists
  unless demo_user.owned_accounts.exists?
    demo_account = Account.create!(name: "Demo's Account", owner: demo_user)
    AccountMembership.create!(account: demo_account, user: demo_user, role: "owner")
    puts "Created account for demo user: #{demo_account.name}"
  end

  # Create a second user for multi-tenancy testing
  test_user = User.find_or_create_by!(email_address: "test@example.com") do |user|
    user.password = "password123"
    user.password_confirmation = "password123"
  end
  puts "Created test user: #{test_user.email_address}"

  # Create account for test user if not exists
  unless test_user.owned_accounts.exists?
    test_account = Account.create!(name: "Test's Account", owner: test_user)
    AccountMembership.create!(account: test_account, user: test_user, role: "owner")
    puts "Created account for test user: #{test_account.name}"
  end

  # Create agents for demo user
  agents_data = [
    {
      name: "Code Review Assistant",
      description: "Reviews code for best practices, security issues, and suggests improvements.",
      provider: "openai",
      model: "gpt-4o",
      preset_type: "terminal",
      appearance: { hat: "fedora", heldItem: "terminal" },
      instructions: "You are a senior code reviewer. Analyze code for:\n- Security vulnerabilities\n- Performance issues\n- Best practices\n- Code style and readability\n\nProvide specific, actionable feedback.",
      instruction_sets: %w[github ruby rails],
      tools: %w[terminal code filesystem],
      model_config: { temperature: 0.3 },
      status: :active
    },
    {
      name: "Documentation Writer",
      description: "Generates technical documentation, README files, and API docs.",
      provider: "anthropic",
      model: "claude-sonnet-5",
      preset_type: "writing",
      appearance: { hat: "fedora", hatAccessory: "feather", heldItem: "scroll" },
      instructions: "You are a technical writer specializing in software documentation. Create clear, comprehensive documentation that is:\n- Well-structured\n- Easy to understand\n- Includes examples\n- Follows best practices",
      instruction_sets: [],
      tools: %w[edit filesystem],
      model_config: { temperature: 0.5 },
      status: :active
    },
    {
      name: "Data Pipeline Agent",
      description: "Helps design and implement data processing pipelines.",
      provider: "openai",
      model: "gpt-4o-mini",
      preset_type: "documentAnalysis",
      appearance: { hat: "fedora", heldItem: "document" },
      instructions: "You are a data engineer. Help with:\n- ETL pipeline design\n- Data transformation logic\n- Query optimization\n- Data quality checks",
      instruction_sets: %w[python],
      tools: %w[code database filesystem],
      model_config: { temperature: 0.2 },
      status: :draft
    }
  ]

  # Agent definitions only - no fabricated runs, outputs or metrics. Run
  # stats, traces, generations and evaluation scores populate exclusively
  # from real executions (configure provider credentials and run an agent).
  agents_data.each do |agent_data|
    agent = demo_user.agents.find_or_create_by!(name: agent_data[:name]) do |a|
      a.assign_attributes(agent_data)
    end
    puts "Created agent: #{agent.name} (#{agent.status})"
  end

  # Create an agent for test_user to verify multi-tenancy
  test_agent = test_user.agents.find_or_create_by!(name: "Test User Agent") do |a|
    a.description = "Agent belonging to test user for multi-tenancy testing"
    a.provider = "openai"
    a.model = "gpt-4o-mini"
    a.preset_type = "terminal"
    a.status = :active
  end
  puts "Created test user agent: #{test_agent.name}"

  puts "\nSeed Summary:"
  puts "  Users: #{User.count}"
  puts "  Agents: #{Agent.count}"
  puts "  Agent Templates: #{AgentTemplate.count}"
  # Runs and versions are no longer seeded, so reporting their counts here
  # only ever printed 0 and read as a failed seed rather than a deliberate one.
  puts "  Agent Runs: 0 seeded (populate by running an agent)"
end

# Pricing Plans
plans = [
  {
    name: "ActiveAgent.dev",
    slug: "free",
    price_cents: 0,
    annual_price_cents: 0,
    trial_days: 0,
    included_seats: 1,
    # Every signup gets a default workspace (see RegistrationsController)
    included_workspaces: 1,
    features: {
      "web_ui_dashboard" => true,
      "action_prompt" => true,
      "solid_agent" => true,
      "streaming" => true,
      "structured_outputs" => true,
      "error_handling" => true,
      "community_support" => true,
      "observability_trial" => true
    }
  },
  {
    name: "ActiveAgent.PRO",
    slug: "pro",
    price_cents: 9900,
    annual_price_cents: 99_500,
    stripe_monthly_price_id: ENV["STRIPE_PRO_MONTHLY_PRICE_ID"],
    stripe_annual_price_id: ENV["STRIPE_PRO_ANNUAL_PRICE_ID"],
    trial_days: 14,
    included_seats: 5,
    included_workspaces: 1,
    features: {
      "web_ui_dashboard" => true,
      "action_prompt" => true,
      "solid_agent" => true,
      "streaming" => true,
      "structured_outputs" => true,
      "error_handling" => true,
      "generational_versioning" => true,
      "multi_agent_workflows" => true,
      "reasonable_reasons" => true,
      "generative_ui" => true,
      "human_in_the_loop" => true,
      "cost_analytics" => true,
      "ab_testing" => true,
      "email_support" => true,
      "10k_runs_monthly" => true,
      "traces_25k_monthly" => true,
      "14_day_retention" => true
    }
  },
  {
    name: "ActiveAgent Enterprise",
    slug: "enterprise",
    price_cents: 26_900,
    annual_price_cents: 269_000,
    stripe_monthly_price_id: ENV["STRIPE_ENTERPRISE_MONTHLY_PRICE_ID"],
    stripe_annual_price_id: ENV["STRIPE_ENTERPRISE_ANNUAL_PRICE_ID"],
    trial_days: 0,
    included_seats: -1,
    included_workspaces: -1,
    features: {
      "web_ui_dashboard" => true,
      "action_prompt" => true,
      "solid_agent" => true,
      "streaming" => true,
      "structured_outputs" => true,
      "error_handling" => true,
      "generational_versioning" => true,
      "multi_agent_workflows" => true,
      "reasonable_reasons" => true,
      "generative_ui" => true,
      "human_in_the_loop" => true,
      "cost_analytics" => true,
      "ab_testing" => true,
      "generative_workflow_generators" => true,
      "deterministic_generative_tasks" => true,
      "multi_app_licensing" => true,
      "sso" => true,
      "soc2_hipaa" => true,
      "private_vpc" => true,
      "dedicated_support" => true,
      "traces_500k_monthly" => true,
      "400_day_retention" => true,
      "4_hour_sla" => true
    }
  }
]

plans.each do |plan_attrs|
  plan = Plan.find_or_initialize_by(slug: plan_attrs[:slug])
  plan.assign_attributes(plan_attrs)
  plan.save!
  puts "#{plan.persisted? && !plan.previously_new_record? ? 'Updated' : 'Created'} plan: #{plan.name} (#{plan.slug})"
end

puts "\nSeeded #{Plan.count} plans."
