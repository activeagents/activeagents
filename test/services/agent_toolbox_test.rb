# frozen_string_literal: true

require "test_helper"

class AgentToolboxTest < ActiveSupport::TestCase
  test "definitions_for maps supported agent tools and skips the rest" do
    definitions = AgentToolbox.definitions_for(%w[fetch search code terminal playwright agents])

    assert_equal %w[fetch_url web_search calculate browse_page call_agent], definitions.map { |d| d[:name] }
    definitions.each do |definition|
      assert definition[:description].present?
      assert_equal "object", definition.dig(:parameters, :type)
    end
  end

  test "browse_page rejects hosts outside the trusted allowlist" do
    result = AgentToolbox.call("browse_page", url: "https://example.com/docs")

    assert_match(/limited to trusted hosts/, result[:error])
  end

  test "extract_links keeps same-site paths with text and drops the rest" do
    html = <<~HTML
      <a href="/agents">Agents Guide</a>
      <a href="providers.html"><span>Providers</span></a>
      <a href="https://docs.activeagents.ai/tools#anchor">Tools</a>
      <a href="https://github.com/activeagents">GitHub</a>
      <a href="mailto:hi@example.com">Mail</a>
      <a href="/agents">Duplicate</a>
    HTML

    links = AgentToolbox.extract_links(html, "https://docs.activeagents.ai/docs/")

    assert_equal [
      { path: "/agents", text: "Agents Guide" },
      { path: "/docs/providers.html", text: "Providers" },
      { path: "/tools", text: "Tools" }
    ], links
  end

  test "definitions_for handles nil and empty tool lists" do
    assert_equal [], AgentToolbox.definitions_for(nil)
    assert_equal [], AgentToolbox.definitions_for([])
  end

  test "call returns an error hash for unknown tools" do
    result = AgentToolbox.call("rm_rf", path: "/")

    assert_equal "Unknown tool: rm_rf", result[:error]
  end

  test "call returns an error hash for bad arguments instead of raising" do
    result = AgentToolbox.call("calculate", wrong_kwarg: "2+2")

    assert_match(/Invalid arguments for calculate/, result[:error])
  end

  test "calculate evaluates arithmetic" do
    assert_equal 14, AgentToolbox.calculate(expression: "2 + 3 * 4")[:result]
    assert_equal 22.5, AgentToolbox.calculate(expression: "(2 + 3) * 4.5")[:result]
    assert_equal(-6, AgentToolbox.calculate(expression: "-2 * 3")[:result])
    assert_equal 1, AgentToolbox.calculate(expression: "7 % 3")[:result]
    assert_in_delta 0.333333, AgentToolbox.calculate(expression: "1/3")[:result], 0.0001
  end

  test "calculate rejects division by zero and non-arithmetic input" do
    assert_match(/Division by zero/, AgentToolbox.calculate(expression: "1 / 0")[:error])
    assert_match(/Unsupported characters/, AgentToolbox.calculate(expression: "system('ls')")[:error])
    assert_match(/Empty expression/, AgentToolbox.calculate(expression: "")[:error])
  end

  test "call caches successful results and tags replays" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    first = AgentToolbox.call("calculate", expression: "2+2")
    second = AgentToolbox.call("calculate", expression: "2+2")

    assert_equal 4, first[:result]
    assert_nil first[:cached]
    assert_equal 4, second[:result]
    assert second[:cached], "second identical call should replay the cached result"

    # Error results are never cached — only the successful call's entry
    # remains in the store.
    2.times { AgentToolbox.call("calculate", expression: "1/0") }
    assert_equal 1, Rails.cache.instance_variable_get(:@data).size
  ensure
    Rails.cache = original_cache
  end

  test "fetch_url refuses non-http and private targets" do
    assert_equal "Only http(s) URLs are supported", AgentToolbox.fetch_url(url: "ftp://example.com")[:error]
    assert_equal "URL host is not allowed", AgentToolbox.fetch_url(url: "http://127.0.0.1/latest")[:error]
    assert_equal "URL host is not allowed", AgentToolbox.fetch_url(url: "http://localhost:11434/v1")[:error]
    assert_equal "URL host is not allowed", AgentToolbox.fetch_url(url: "http://10.0.0.8/internal")[:error]
    assert_equal "URL host is not allowed", AgentToolbox.fetch_url(url: "http://169.254.169.254/metadata")[:error]
  end
end
