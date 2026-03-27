# frozen_string_literal: true

require "test_helper"

class BaseToolTest < ActiveSupport::TestCase
  class TestTool < BaseTool
    tool_name "test"
    description "A test tool for unit testing"
    parameter :input, type: "string", description: "Input value", required: true
    parameter :optional_flag, type: "boolean", description: "An optional flag"

    def call(input:, optional_flag: false)
      { input: input, flag: optional_flag }
    end
  end

  test "tool_name returns configured name" do
    assert_equal "test", TestTool.tool_name
  end

  test "description returns configured description" do
    assert_equal "A test tool for unit testing", TestTool.description
  end

  test "to_tool_definition returns LLM-compatible schema" do
    definition = TestTool.to_tool_definition

    assert_equal "test", definition[:name]
    assert_equal "A test tool for unit testing", definition[:description]
    assert_equal "object", definition[:parameters][:type]
    assert_includes definition[:parameters][:required], "input"
    assert definition[:parameters][:properties].key?("input")
    assert definition[:parameters][:properties].key?("optional_flag")
  end

  test "class-level call instantiates and delegates" do
    result = TestTool.call(input: "hello")

    assert_equal "hello", result[:input]
    assert_equal false, result[:flag]
  end

  test "validate_params! raises on missing required params" do
    tool = TestTool.new

    assert_raises(BaseTool::ParameterError) do
      tool.validate_params!({})
    end
  end

  test "validate_params! raises on unknown params" do
    tool = TestTool.new

    assert_raises(BaseTool::ParameterError) do
      tool.validate_params!(input: "hi", unknown: "bad")
    end
  end

  test "validate_params! passes with valid params" do
    tool = TestTool.new

    assert_nothing_raised do
      tool.validate_params!(input: "hi")
    end
  end

  test "base tool raises NotImplementedError" do
    assert_raises(NotImplementedError) do
      BaseTool.new.call
    end
  end
end
