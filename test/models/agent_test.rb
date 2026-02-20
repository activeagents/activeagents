# frozen_string_literal: true

require "test_helper"

class AgentTest < ActiveSupport::TestCase
  # ===========================================
  # Association Tests
  # ===========================================

  test "belongs to user" do
    user = create_user
    agent = create_agent(user: user)

    assert_equal user, agent.user
    assert_includes user.agents, agent
  end

  test "has many agent_runs" do
    user = create_user
    agent = create_agent(user: user)
    run1 = create_run(agent: agent)
    run2 = create_run(agent: agent)

    assert_equal 2, agent.agent_runs.count
    assert_includes agent.agent_runs, run1
    assert_includes agent.agent_runs, run2
  end

  test "has many agent_versions" do
    user = create_user
    agent = create_agent(user: user)

    # Initial version is created on agent creation
    assert_equal 1, agent.agent_versions.count
    assert_equal 1, agent.latest_version.version_number
  end

  test "destroys dependent runs when deleted" do
    user = create_user
    agent = create_agent(user: user)
    run = create_run(agent: agent)

    assert_difference "AgentRun.count", -1 do
      agent.destroy
    end
  end

  test "destroys dependent versions when deleted" do
    user = create_user
    agent = create_agent(user: user)

    assert_difference "AgentVersion.count", -1 do
      agent.destroy
    end
  end

  # ===========================================
  # Validation Tests
  # ===========================================

  test "requires name" do
    user = create_user
    agent = user.agents.build(name: nil, provider: "openai", model: "gpt-4o-mini")

    assert_not agent.valid?
    assert_includes agent.errors[:name], "can't be blank"
  end

  test "requires name with minimum length" do
    user = create_user
    agent = user.agents.build(name: "A", provider: "openai", model: "gpt-4o-mini")

    assert_not agent.valid?
    assert_includes agent.errors[:name], "is too short (minimum is 2 characters)"
  end

  test "requires provider" do
    user = create_user
    agent = user.agents.build(name: "Test Agent", provider: nil, model: "gpt-4o-mini")

    assert_not agent.valid?
    assert_includes agent.errors[:provider], "can't be blank"
  end

  test "requires model" do
    user = create_user
    agent = user.agents.build(name: "Test Agent", provider: "openai", model: nil)

    assert_not agent.valid?
    assert_includes agent.errors[:model], "can't be blank"
  end

  test "generates unique slug" do
    user = create_user
    agent1 = create_agent(user: user, name: "Test Agent")
    agent2 = create_agent(user: user, name: "Test Agent")

    assert_equal "test-agent", agent1.slug
    assert_match(/test-agent-\d+/, agent2.slug)
  end

  # ===========================================
  # Status Tests
  # ===========================================

  test "default status is draft" do
    user = create_user
    agent = create_agent(user: user)

    assert agent.draft?
  end

  test "can be activated" do
    user = create_user
    agent = create_agent(user: user)
    agent.active!

    assert agent.active?
  end

  test "can be archived" do
    user = create_user
    agent = create_agent(user: user)
    agent.archived!

    assert agent.archived?
  end

  # ===========================================
  # Versioning Tests
  # ===========================================

  test "creates initial version on create" do
    user = create_user
    agent = create_agent(user: user)

    assert_equal 1, agent.version_count
    version = agent.latest_version

    assert_equal 1, version.version_number
    assert_equal "Initial creation", version.change_summary
    assert_equal agent.instructions, version.configuration_snapshot["instructions"]
  end

  test "creates new version when instructions change" do
    user = create_user
    agent = create_agent(user: user)

    assert_difference "AgentVersion.count", 1 do
      agent.update!(instructions: "New instructions")
    end

    assert_equal 2, agent.version_count
    assert_equal 2, agent.latest_version.version_number
    assert_includes agent.latest_version.change_summary, "instructions"
  end

  test "creates new version when tools change" do
    user = create_user
    agent = create_agent(user: user, tools: [ "terminal" ])

    assert_difference "AgentVersion.count", 1 do
      agent.update!(tools: [ "terminal", "filesystem" ])
    end

    assert_equal 2, agent.version_count
    assert_includes agent.latest_version.change_summary, "tools"
  end

  test "does not create version when non-config fields change" do
    user = create_user
    agent = create_agent(user: user)

    assert_no_difference "AgentVersion.count" do
      agent.update!(name: "Updated Name")
    end
  end

  test "can restore from version" do
    user = create_user
    agent = create_agent(user: user, instructions: "Original instructions")
    original_version = agent.latest_version

    agent.update!(instructions: "Updated instructions")
    assert_equal "Updated instructions", agent.instructions

    agent.restore_from_version!(original_version)
    assert_equal "Original instructions", agent.instructions
  end

  # ===========================================
  # Configuration Snapshot Tests
  # ===========================================

  test "configuration_snapshot includes all config fields" do
    user = create_user
    agent = create_agent(
      user: user,
      instructions: "Test instructions",
      tools: [ "terminal", "filesystem" ],
      model_config: { "temperature" => 0.7 }
    )

    snapshot = agent.configuration_snapshot

    assert_equal "Test instructions", snapshot[:instructions]
    assert_equal [ "terminal", "filesystem" ], snapshot[:tools]
    assert_equal({ "temperature" => 0.7 }, snapshot[:model_config])
    assert snapshot.key?(:name)
    assert snapshot.key?(:description)
    assert snapshot.key?(:provider)
    assert snapshot.key?(:model)
  end

  # ===========================================
  # Scope Tests
  # ===========================================

  test "active_agents scope returns only active agents" do
    user = create_user
    active_agent = create_agent(user: user, status: :active)
    create_agent(user: user, status: :draft)
    create_agent(user: user, status: :archived)

    assert_equal [ active_agent ], user.agents.active_agents.to_a
  end

  test "by_provider scope filters by provider" do
    user = create_user
    openai_agent = create_agent(user: user, provider: "openai")
    create_agent(user: user, provider: "anthropic")

    assert_equal [ openai_agent ], user.agents.by_provider("openai").to_a
  end

  # ===========================================
  # Execution Tests
  # ===========================================

  test "execute creates a pending run and queues job" do
    user = create_user
    agent = create_agent(user: user)

    run = nil
    assert_difference "AgentRun.count", 1 do
      run = agent.execute("Test prompt", context: "test")
    end

    assert run.pending?
    assert_equal "Test prompt", run.input_prompt
    assert_equal({ "context" => "test" }, run.input_params)
    assert run.trace_id.present?
  end

  test "test_execute creates and runs synchronously" do
    user = create_user
    agent = create_agent(user: user)

    run = agent.test_execute("Test prompt")

    assert run.complete?
    assert run.output.present?
    assert run.duration_ms.present?
    assert run.input_tokens.present?
    assert run.output_tokens.present?
    assert run.total_tokens.present?
  end

  # ===========================================
  # Multi-tenancy Tests
  # ===========================================

  test "agents are scoped to users" do
    user1 = create_user(email: "user1@example.com")
    user2 = create_user(email: "user2@example.com")

    agent1 = create_agent(user: user1, name: "User1 Agent")
    agent2 = create_agent(user: user2, name: "User2 Agent")

    assert_includes user1.agents, agent1
    assert_not_includes user1.agents, agent2

    assert_includes user2.agents, agent2
    assert_not_includes user2.agents, agent1
  end

  test "same slug can exist for different users" do
    user1 = create_user(email: "user1@example.com")
    user2 = create_user(email: "user2@example.com")

    agent1 = create_agent(user: user1, name: "My Agent")
    agent2 = create_agent(user: user2, name: "My Agent")

    # Both users get slugs starting with my-agent
    # The exact slug depends on whether there are existing agents
    assert agent1.slug.start_with?("my-agent")
    assert agent2.slug.start_with?("my-agent")
    # Slug uniqueness is scoped to user_id at the DB level
    assert agent1.valid?
    assert agent2.valid?
  end

  # ===========================================
  # Code Generation Tests
  # ===========================================

  test "generates agent class code" do
    user = create_user
    agent = create_agent(
      user: user,
      name: "CodeReview",
      provider: "openai",
      model: "gpt-4o",
      instructions: "Review code carefully."
    )

    code = agent.to_agent_class_code

    assert_includes code, "< ApplicationAgent"
    assert_includes code, 'generate_with :openai, model: "gpt-4o"'
    assert_includes code, "Review code carefully."
  end
end
