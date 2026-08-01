# frozen_string_literal: true

require "test_helper"

class ModelContextWindowTest < ActiveSupport::TestCase
  test "uses the RubyLLM registry window for known models" do
    assert_equal 128_000, ModelContextWindow.for("gpt-4o-mini")
    assert_equal 200_000, ModelContextWindow.for("claude-sonnet-4-5")
  end

  test "falls back to the static table for models the registry doesn't know" do
    assert_equal 128_000, ModelContextWindow.static_window("llama3.1:70b")
    assert_equal 32_768, ModelContextWindow.static_window("qwen3:8b")
    assert_equal 8_192, ModelContextWindow.static_window("gpt-4")
    assert_equal 32_768, ModelContextWindow.static_window("gpt-4-32k")
  end

  test "static patterns match the most specific id first" do
    # gpt-4o and gpt-4-32k must not be swallowed by the bare gpt-4 pattern
    assert_equal 128_000, ModelContextWindow.static_window("gpt-4o-2024-08-06")
    assert_equal 32_768, ModelContextWindow.static_window("gpt-4-32k-0613")
  end

  test "defaults for unknown models and reports the window as unknown" do
    assert_equal ModelContextWindow::DEFAULT_WINDOW, ModelContextWindow.for("totally-unknown-model-xyz")
    assert_not ModelContextWindow.known?("totally-unknown-model-xyz")
    assert_not ModelContextWindow.known?(nil)
  end

  test "known? is true once a window resolves" do
    assert ModelContextWindow.known?("gpt-4o-mini")
    assert ModelContextWindow.known?("qwen3:8b")
  end
end
