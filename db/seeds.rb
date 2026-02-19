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
      model: "claude-sonnet-4-20250514",
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

  agents_data.each do |agent_data|
    agent = demo_user.agents.find_or_create_by!(name: agent_data[:name]) do |a|
      a.assign_attributes(agent_data)
    end
    puts "Created agent: #{agent.name} (#{agent.status})"

    # Create some agent runs for active agents
    next unless agent.active?

    # Generate runs over the past 30 days
    run_scenarios = [
      {
        input_prompt: "Review this Ruby method for potential issues:\n\ndef process_user(params)\n  user = User.find(params[:id])\n  user.update(params.permit!)\n  redirect_to user\nend",
        output: "I've identified several issues with this code:\n\n1. **Security Vulnerability - Mass Assignment**: Using `params.permit!` allows all parameters, which is a serious security risk. Use strong parameters instead:\n   ```ruby\n   params.require(:user).permit(:name, :email)\n   ```\n\n2. **Missing Error Handling**: No handling for when user is not found. Add:\n   ```ruby\n   user = User.find_by(id: params[:id])\n   return render_not_found unless user\n   ```\n\n3. **No Authorization Check**: Verify the current user can update this user.\n\n4. **Consider using `update!`** to raise on failure, or check the return value.",
        status: :complete,
        input_tokens: 45,
        output_tokens: 180,
        duration_ms: 2340
      },
      {
        input_prompt: "What are the best practices for Rails API authentication?",
        output: "Here are the recommended best practices for Rails API authentication:\n\n## 1. Use Token-Based Authentication\n- JWT (JSON Web Tokens) for stateless auth\n- Consider using gems like `devise-jwt` or `knock`\n\n## 2. Secure Token Storage\n- Never store tokens in localStorage (XSS vulnerable)\n- Use httpOnly cookies when possible\n\n## 3. Implement Token Refresh\n- Short-lived access tokens (15-60 min)\n- Longer-lived refresh tokens\n\n## 4. Rate Limiting\n- Implement rate limiting on auth endpoints\n- Use `rack-attack` gem\n\n## 5. HTTPS Only\n- Force SSL in production\n- Use secure cookies",
        status: :complete,
        input_tokens: 12,
        output_tokens: 210,
        duration_ms: 3120
      },
      {
        input_prompt: "Explain this error: undefined method `each' for nil:NilClass",
        output: "This error occurs when you try to call `.each` on a variable that is `nil` instead of an array or enumerable.\n\n**Common causes:**\n1. Database query returned nil\n2. Missing association\n3. Uninitialized variable\n\n**Solutions:**\n- Add nil check: `items&.each { |i| ... }`\n- Use empty array default: `(items || []).each`\n- Ensure data exists before iterating",
        status: :complete,
        input_tokens: 15,
        output_tokens: 95,
        duration_ms: 1560
      },
      {
        input_prompt: "Generate test cases for a user registration endpoint",
        output: nil,
        error_message: "API rate limit exceeded. Please retry in 60 seconds.",
        status: :failed,
        input_tokens: 10,
        output_tokens: 0,
        duration_ms: 450
      },
      {
        input_prompt: "Analyze this SQL query for performance:\nSELECT * FROM orders JOIN users ON orders.user_id = users.id WHERE orders.created_at > '2024-01-01'",
        output: "**Query Analysis:**\n\n1. **Avoid SELECT ***: Only select needed columns to reduce data transfer.\n\n2. **Add Index**: Ensure index on `orders.created_at` and `orders.user_id`:\n   ```sql\n   CREATE INDEX idx_orders_created_at ON orders(created_at);\n   CREATE INDEX idx_orders_user_id ON orders(user_id);\n   ```\n\n3. **Consider Partitioning**: For large tables, partition by date.\n\n4. **Optimized Query**:\n   ```sql\n   SELECT o.id, o.total, u.email\n   FROM orders o\n   JOIN users u ON o.user_id = u.id\n   WHERE o.created_at > '2024-01-01'\n   ```",
        status: :complete,
        input_tokens: 35,
        output_tokens: 165,
        duration_ms: 2890
      }
    ]

    run_scenarios.each_with_index do |scenario, index|
      # Spread runs over the past 30 days
      created_at = (30 - index * 5).days.ago + rand(0..24).hours

      run = agent.agent_runs.create!(
        input_prompt: scenario[:input_prompt],
        input_params: { source: "seed" },
        output: scenario[:output],
        output_metadata: scenario[:output] ? { model: agent.model, provider: agent.provider } : {},
        status: scenario[:status],
        input_tokens: scenario[:input_tokens],
        output_tokens: scenario[:output_tokens],
        total_tokens: (scenario[:input_tokens] || 0) + (scenario[:output_tokens] || 0),
        duration_ms: scenario[:duration_ms],
        error_message: scenario[:error_message],
        started_at: created_at,
        completed_at: created_at + ((scenario[:duration_ms] || 0) / 1000.0).seconds,
        created_at: created_at,
        updated_at: created_at
      )
      puts "  - Created run #{run.id} (#{run.status}) for #{agent.name}"
    end

    # Create a version history for the agent
    agent.update!(instructions: agent.instructions + "\n\nAlways be concise.")
    puts "  - Created version history for #{agent.name}"
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

  # Create a run for test user's agent
  test_agent.agent_runs.find_or_create_by!(input_prompt: "Hello from test user") do |run|
    run.output = "Hello! How can I help you today?"
    run.status = :complete
    run.input_tokens = 5
    run.output_tokens = 10
    run.total_tokens = 15
    run.duration_ms = 800
    run.started_at = 1.day.ago
    run.completed_at = 1.day.ago + 0.8.seconds
  end
  puts "Created test user agent run"

  puts "\nSeed Summary:"
  puts "  Users: #{User.count}"
  puts "  Agents: #{Agent.count}"
  puts "  Agent Runs: #{AgentRun.count}"
  puts "  Agent Versions: #{AgentVersion.count}"
  puts "  Agent Templates: #{AgentTemplate.count}"
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
    included_workspaces: 0,
    features: {
      "web_ui_dashboard" => true,
      "action_prompt" => true,
      "solid_agent" => true,
      "streaming" => true,
      "structured_outputs" => true,
      "error_handling" => true,
      "community_support" => true
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
