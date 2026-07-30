# frozen_string_literal: true

require "test_helper"

class ModelPricingTest < ActiveSupport::TestCase
  test "uses RubyLLM registry rates for known models" do
    input_rate, output_rate = ModelPricing.rate_for("gpt-4o")

    # Registry rates (USD per 1M tokens), maintained upstream by RubyLLM
    assert_equal 2.5, input_rate
    assert_equal 10.0, output_rate
  end

  test "falls back to the static table for models the registry doesn't know" do
    assert_equal [ 0.0, 0.0 ], ModelPricing.rate_for("mock-provider-model")
  end

  test "falls back to the blended default rate for unknown models" do
    assert_equal ModelPricing::DEFAULT_RATE, ModelPricing.rate_for("totally-unknown-model-xyz")
  end

  test "static table covers current Claude models at their launch rates" do
    assert_equal [ 3.00, 15.00 ], ModelPricing.static_rate("claude-sonnet-5")
    assert_equal [ 5.00, 25.00 ], ModelPricing.static_rate("claude-opus-5")
    assert_equal [ 5.00, 25.00 ], ModelPricing.static_rate("claude-opus-4-5-20251101")
    assert_equal [ 10.00, 50.00 ], ModelPricing.static_rate("claude-fable-5")
    assert_equal [ 1.00, 5.00 ], ModelPricing.static_rate("claude-haiku-4-5")
    # Older generations keep their legacy rates
    assert_equal [ 0.80, 4.00 ], ModelPricing.static_rate("claude-3-5-haiku-latest")
    assert_equal [ 15.00, 75.00 ], ModelPricing.static_rate("claude-3-opus-20240229")
  end

  test "estimate prices input and output tokens separately" do
    cost = ModelPricing.estimate(model: "gpt-4o", input_tokens: 1_000_000, output_tokens: 1_000_000)

    assert_in_delta 12.5, cost, 0.001
  end

  test "estimate returns nil when there is nothing to price" do
    assert_nil ModelPricing.estimate(model: "gpt-4o", input_tokens: 0, output_tokens: 0)
  end
end
