# frozen_string_literal: true

require "test_helper"

class PromptsToolTest < ActiveSupport::TestCase
  test "tool definition is valid" do
    definition = PromptsTool.to_tool_definition

    assert_equal "prompts", definition[:name]
    assert definition[:description].present?
    assert_includes definition[:parameters][:required], "operation"
  end

  test "build substitutes variables into template" do
    result = PromptsTool.call(
      operation: "build",
      template: "You are a {role}. Please {task}.",
      variables: { "role" => "code reviewer", "task" => "review this PR" }
    )

    assert_equal "You are a code reviewer. Please review this PR.", result[:prompt]
    assert_includes result[:variables_used], "role"
    assert_includes result[:variables_used], "task"
    assert_empty result[:unresolved]
  end

  test "build reports unresolved variables" do
    result = PromptsTool.call(
      operation: "build",
      template: "Hello {name}, your {missing_var} is ready",
      variables: { "name" => "Alice" }
    )

    assert_includes result[:prompt], "Hello Alice"
    assert_includes result[:unresolved], "missing_var"
  end

  test "build appends context" do
    result = PromptsTool.call(
      operation: "build",
      template: "Analyze this",
      variables: {},
      context: { "language" => "Ruby", "framework" => "Rails" }
    )

    assert_includes result[:prompt], "Context:"
    assert_includes result[:prompt], "language: Ruby"
    assert_includes result[:prompt], "framework: Rails"
  end

  test "compose creates message array" do
    result = PromptsTool.call(
      operation: "compose",
      parts: [
        { "role" => "system", "content" => "You are helpful" },
        { "role" => "user", "content" => "What is Ruby?" }
      ]
    )

    assert_equal 2, result[:part_count]
    assert_equal "system", result[:messages][0][:role]
    assert_equal "user", result[:messages][1][:role]
  end

  test "compose adds context as system message" do
    result = PromptsTool.call(
      operation: "compose",
      parts: [{ "role" => "user", "content" => "Hello" }],
      context: { "mode" => "test" }
    )

    assert_equal 2, result[:part_count]
    assert_equal "system", result[:messages][0][:role]
    assert_includes result[:messages][0][:content], "mode: test"
  end

  test "compose rejects invalid roles" do
    assert_raises(BaseTool::ParameterError) do
      PromptsTool.call(
        operation: "compose",
        parts: [{ "role" => "hacker", "content" => "bad" }]
      )
    end
  end

  test "list returns available prompts" do
    user = create_user
    create_agent(user: user, name: "Prompted Agent", status: :active, instructions: "Test instructions")

    result = PromptsTool.call(operation: "list")

    assert result[:count] > 0
    names = result[:prompts].map { |p| p[:name] }
    assert_includes names, "Prompted Agent"
  end

  test "from_agent loads agent prompt" do
    user = create_user
    agent = create_agent(user: user, name: "Prompt Source", instructions: "Be helpful and concise")

    result = PromptsTool.call(operation: "from_agent", agent_name: agent.slug)

    assert_equal "Prompt Source", result[:agent]
    assert_equal "Be helpful and concise", result[:prompt]
  end

  test "from_agent raises for unknown agent" do
    assert_raises(BaseTool::ExecutionError) do
      PromptsTool.call(operation: "from_agent", agent_name: "nonexistent-xyz")
    end
  end

  test "build requires template" do
    assert_raises(BaseTool::ParameterError) do
      PromptsTool.call(operation: "build")
    end
  end

  test "compose requires parts" do
    assert_raises(BaseTool::ParameterError) do
      PromptsTool.call(operation: "compose")
    end
  end

  test "rejects unknown operations" do
    assert_raises(BaseTool::ParameterError) do
      PromptsTool.call(operation: "unknown")
    end
  end
end
