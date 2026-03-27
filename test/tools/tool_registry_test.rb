# frozen_string_literal: true

require "test_helper"

class ToolRegistryTest < ActiveSupport::TestCase
  test "resolve returns tool class for known tools" do
    assert_equal FetchTool, ToolRegistry.resolve("fetch")
    assert_equal FilesystemTool, ToolRegistry.resolve("filesystem")
    assert_equal BashTool, ToolRegistry.resolve("bash")
    assert_equal AgentsTool, ToolRegistry.resolve("agents")
    assert_equal ViewsTool, ToolRegistry.resolve("views")
    assert_equal PromptsTool, ToolRegistry.resolve("prompts")
  end

  test "resolve returns nil for unknown tools" do
    assert_nil ToolRegistry.resolve("nonexistent")
    assert_nil ToolRegistry.resolve("")
  end

  test "resolve_all returns classes for known tools and skips unknown" do
    result = ToolRegistry.resolve_all(%w[fetch bash nonexistent])

    assert_equal [FetchTool, BashTool], result
  end

  test "resolve_all handles empty array" do
    assert_equal [], ToolRegistry.resolve_all([])
  end

  test "definitions_for returns tool definitions" do
    definitions = ToolRegistry.definitions_for(%w[fetch bash])

    assert_equal 2, definitions.size
    assert_equal "fetch", definitions[0][:name]
    assert_equal "bash", definitions[1][:name]
    assert definitions[0][:parameters].present?
  end

  test "available_tools returns all tools" do
    tools = ToolRegistry.available_tools

    assert_equal 6, tools.size
    assert tools.key?("fetch")
    assert tools.key?("filesystem")
    assert tools.key?("bash")
    assert tools.key?("agents")
    assert tools.key?("views")
    assert tools.key?("prompts")
  end

  test "tool_metadata returns metadata for all tools" do
    metadata = ToolRegistry.tool_metadata

    assert_equal 6, metadata.size
    metadata.each do |tool|
      assert tool[:name].present?
      assert tool[:display_name].present?
      assert tool[:description].present?
      assert tool[:parameters].present?
    end
  end

  test "execute dispatches to correct tool" do
    # Use prompts tool with build operation since it doesn't need external deps
    result = ToolRegistry.execute(
      "prompts",
      operation: "build",
      template: "Hello {name}",
      variables: { "name" => "World" }
    )

    assert_equal "Hello World", result[:prompt]
  end

  test "execute raises for unknown tool" do
    assert_raises(BaseTool::ToolError) do
      ToolRegistry.execute("nonexistent")
    end
  end
end
