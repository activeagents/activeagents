# frozen_string_literal: true

require "test_helper"

class AgentInstructionTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @agent = create_agent(user: @user)
  end

  test "belongs to agent" do
    instruction = @agent.agent_instructions.create!(
      name: "safety",
      content: "Be safe",
      scope: "system"
    )
    assert_equal @agent, instruction.agent
  end

  test "validates name presence" do
    instruction = @agent.agent_instructions.build(content: "test", scope: "system")
    assert_not instruction.valid?
  end

  test "validates content presence" do
    instruction = @agent.agent_instructions.build(name: "test", scope: "system")
    assert_not instruction.valid?
  end

  test "validates scope inclusion" do
    instruction = @agent.agent_instructions.build(
      name: "test",
      content: "test",
      scope: "invalid"
    )
    assert_not instruction.valid?
  end

  test "name is unique per agent" do
    @agent.agent_instructions.create!(name: "safety", content: "v1", scope: "system")
    duplicate = @agent.agent_instructions.build(name: "safety", content: "v2", scope: "system")
    assert_not duplicate.valid?
  end

  test "compose joins instructions by priority" do
    @agent.agent_instructions.create!(name: "first", content: "Be helpful", scope: "system", priority: 10)
    @agent.agent_instructions.create!(name: "second", content: "Be safe", scope: "system", priority: 5)
    @agent.agent_instructions.create!(name: "third", content: "Be concise", scope: "system", priority: 1)

    composed = @agent.agent_instructions.system_instructions.compose
    assert_equal "Be helpful\n\nBe safe\n\nBe concise", composed
  end

  test "system_instructions scope filters by system scope" do
    system = @agent.agent_instructions.create!(name: "sys", content: "system", scope: "system")
    @agent.agent_instructions.create!(name: "usr", content: "user", scope: "user")

    results = @agent.agent_instructions.system_instructions
    assert_includes results, system
    assert_equal 1, results.count
  end
end
