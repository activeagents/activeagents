# frozen_string_literal: true

require "test_helper"

class AgentToolsetTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @agent = create_agent(user: @user)
  end

  test "belongs to agent" do
    toolset = @agent.agent_toolsets.create!(name: "basics", tools: %w[fetch bash])
    assert_equal @agent, toolset.agent
  end

  test "validates name presence" do
    toolset = @agent.agent_toolsets.build(tools: %w[fetch])
    assert_not toolset.valid?
  end

  test "name is unique per agent" do
    @agent.agent_toolsets.create!(name: "basics", tools: %w[fetch])
    duplicate = @agent.agent_toolsets.build(name: "basics", tools: %w[bash])
    assert_not duplicate.valid?
  end

  test "enabled scope filters enabled toolsets" do
    enabled = @agent.agent_toolsets.create!(name: "enabled", tools: %w[fetch], enabled: true)
    disabled = @agent.agent_toolsets.create!(name: "disabled", tools: %w[bash], enabled: false)

    results = @agent.agent_toolsets.enabled
    assert_includes results, enabled
    assert_not_includes results, disabled
  end

  test "resolved_tools aggregates tools from enabled toolsets" do
    @agent.agent_toolsets.create!(name: "web", tools: %w[fetch views], enabled: true)
    @agent.agent_toolsets.create!(name: "dev", tools: %w[bash fetch], enabled: true)
    @agent.agent_toolsets.create!(name: "disabled", tools: %w[agents], enabled: false)

    resolved = @agent.agent_toolsets.resolved_tools
    assert_includes resolved, "fetch"
    assert_includes resolved, "views"
    assert_includes resolved, "bash"
    assert_not_includes resolved, "agents"
    # No duplicates
    assert_equal resolved.uniq, resolved
  end

  test "tool_definitions returns ToolRegistry definitions" do
    toolset = @agent.agent_toolsets.create!(name: "web", tools: %w[fetch prompts])
    definitions = toolset.tool_definitions

    assert_equal 2, definitions.size
    assert_equal "fetch", definitions[0][:name]
    assert_equal "prompts", definitions[1][:name]
  end
end
