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

  test "estimate prices input and output tokens separately" do
    cost = ModelPricing.estimate(model: "gpt-4o", input_tokens: 1_000_000, output_tokens: 1_000_000)

    assert_in_delta 12.5, cost, 0.001
  end

  test "estimate returns nil when there is nothing to price" do
    assert_nil ModelPricing.estimate(model: "gpt-4o", input_tokens: 0, output_tokens: 0)
  end
end
