# frozen_string_literal: true

require "test_helper"

class AgentsToolTest < ActiveSupport::TestCase
  test "tool definition is valid" do
    definition = AgentsTool.to_tool_definition

    assert_equal "agents", definition[:name]
    assert definition[:description].present?
    assert_includes definition[:parameters][:required], "operation"
  end

  test "list returns agent classes and db agents" do
    result = AgentsTool.call(operation: "list")

    assert result.key?(:agent_classes)
    assert result.key?(:stored_agents)
    assert result.key?(:total)
  end

  test "list includes active database agents" do
    user = create_user
    agent = create_agent(user: user, name: "Listed Agent", status: :active)

    result = AgentsTool.call(operation: "list")

    slugs = result[:stored_agents].map { |a| a[:slug] }
    assert_includes slugs, agent.slug
  end

  test "list does not include draft agents" do
    user = create_user
    agent = create_agent(user: user, name: "Draft Agent", status: :draft)

    result = AgentsTool.call(operation: "list")

    slugs = result[:stored_agents].map { |a| a[:slug] }
    assert_not_includes slugs, agent.slug
  end

  test "invoke requires agent_name" do
    assert_raises(BaseTool::ParameterError) do
      AgentsTool.call(operation: "invoke", input: "test")
    end
  end

  test "invoke requires input" do
    assert_raises(BaseTool::ParameterError) do
      AgentsTool.call(operation: "invoke", agent_name: "test")
    end
  end

  test "invoke raises for unknown agent" do
    assert_raises(BaseTool::ExecutionError) do
      AgentsTool.call(operation: "invoke", agent_name: "nonexistent-agent-xyz", input: "test")
    end
  end

  test "invoke calls database agent by slug" do
    user = create_user
    agent = create_agent(user: user, name: "Invokable Agent", status: :active)

    result = AgentsTool.call(operation: "invoke", agent_name: agent.slug, input: "Hello")

    assert_equal agent.name, result[:agent]
    assert result[:output].present?
    assert result[:run_id].present?
  end

  test "rejects unknown operations" do
    assert_raises(BaseTool::ParameterError) do
      AgentsTool.call(operation: "unknown")
    end
  end
end
