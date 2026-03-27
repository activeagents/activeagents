# frozen_string_literal: true

require "test_helper"

class ViewsToolTest < ActiveSupport::TestCase
  test "tool definition is valid" do
    definition = ViewsTool.to_tool_definition

    assert_equal "views", definition[:name]
    assert definition[:description].present?
    assert_includes definition[:parameters][:required], "operation"
  end

  test "list returns available templates" do
    result = ViewsTool.call(operation: "list")

    assert result.key?(:templates)
    assert result.key?(:count)
    assert_kind_of Array, result[:templates]
  end

  test "render requires template" do
    assert_raises(BaseTool::ParameterError) do
      ViewsTool.call(operation: "render")
    end
  end

  test "render rejects directory traversal" do
    assert_raises(BaseTool::ParameterError) do
      ViewsTool.call(operation: "render", template: "../../../etc/passwd")
    end
  end

  test "render rejects absolute paths" do
    assert_raises(BaseTool::ParameterError) do
      ViewsTool.call(operation: "render", template: "/etc/passwd")
    end
  end

  test "render rejects templates outside allowed directories" do
    assert_raises(BaseTool::ParameterError) do
      ViewsTool.call(operation: "render", template: "admin/secrets")
    end
  end

  test "rejects unknown operations" do
    assert_raises(BaseTool::ParameterError) do
      ViewsTool.call(operation: "unknown")
    end
  end
end
