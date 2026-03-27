# frozen_string_literal: true

require "test_helper"

class FetchToolTest < ActiveSupport::TestCase
  test "tool definition is valid" do
    definition = FetchTool.to_tool_definition

    assert_equal "fetch", definition[:name]
    assert definition[:description].present?
    assert_includes definition[:parameters][:required], "url"
  end

  test "rejects non-http URLs" do
    assert_raises(BaseTool::ParameterError) do
      FetchTool.call(url: "ftp://example.com")
    end
  end

  test "rejects invalid URLs" do
    assert_raises(BaseTool::ParameterError) do
      FetchTool.call(url: "not-a-url")
    end
  end

  test "blocks private IP addresses" do
    assert_raises(BaseTool::ParameterError) do
      FetchTool.call(url: "http://192.168.1.1/secret")
    end
  end

  test "blocks localhost" do
    assert_raises(BaseTool::ParameterError) do
      FetchTool.call(url: "http://localhost:3000/admin")
    end
  end

  test "blocks loopback addresses" do
    assert_raises(BaseTool::ParameterError) do
      FetchTool.call(url: "http://127.0.0.1/admin")
    end
  end

  test "strip_html_tags removes tags" do
    tool = FetchTool.new
    result = tool.send(:strip_html_tags, "<p>Hello <strong>world</strong></p>")

    assert_equal "Hello world", result
  end

  test "strip_html_tags removes script tags" do
    tool = FetchTool.new
    result = tool.send(:strip_html_tags, "<script>alert('xss')</script>Hello")

    assert_equal "Hello", result.strip
  end

  test "html_to_markdown converts headings" do
    tool = FetchTool.new
    result = tool.send(:html_to_markdown, "<h1>Title</h1><p>Body text</p>")

    assert_includes result, "# Title"
    assert_includes result, "Body text"
  end

  test "truncate_content enforces max length" do
    tool = FetchTool.new
    long_content = "x" * 200_000
    result = tool.send(:truncate_content, long_content)

    assert result.length <= FetchTool::MAX_CONTENT_LENGTH + 3 # truncation marker
  end
end
