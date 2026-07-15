# frozen_string_literal: true

# Estimates LLM spend from token counts. The activeagent gem's telemetry
# records tokens only; the platform layers pricing on top for the cost
# figures shown in Traces and Metrics.
#
# Prices are USD per million tokens [input, output]. Patterns match the
# denormalized model string from telemetry llm spans. Unknown models fall
# back to a conservative blended rate so totals stay meaningful; costs are
# always presented as estimates.
class ModelPricing
  PRICES = [
    # [pattern, input $/1M, output $/1M]
    [ /gpt-4o-mini/i, 0.15, 0.60 ],
    [ /gpt-4o/i, 2.50, 10.00 ],
    [ /gpt-4\.1-nano/i, 0.10, 0.40 ],
    [ /gpt-4\.1-mini/i, 0.40, 1.60 ],
    [ /gpt-4\.1/i, 2.00, 8.00 ],
    [ /o3-mini|o4-mini/i, 1.10, 4.40 ],
    [ /claude.*(haiku)/i, 0.80, 4.00 ],
    [ /claude.*(sonnet)/i, 3.00, 15.00 ],
    [ /claude.*(opus)/i, 15.00, 75.00 ],
    [ /gemini.*flash/i, 0.10, 0.40 ],
    [ /gemini.*pro/i, 1.25, 10.00 ],
    [ /llama|mistral|mixtral|qwen|deepseek/i, 0.20, 0.60 ],
    [ /mock/i, 0.0, 0.0 ]
  ].freeze

  # Fallback blended rate for unknown models ($/1M input, $/1M output)
  DEFAULT_RATE = [ 1.00, 4.00 ].freeze

  # @return [Float, nil] estimated USD cost, nil when there is nothing to price
  def self.estimate(model:, input_tokens:, output_tokens:)
    input = input_tokens.to_i
    output = output_tokens.to_i
    return nil if input.zero? && output.zero?

    input_rate, output_rate = rate_for(model)
    ((input * input_rate) + (output * output_rate)) / 1_000_000.0
  end

  def self.rate_for(model)
    return DEFAULT_RATE if model.blank?

    PRICES.each do |pattern, input_rate, output_rate|
      return [ input_rate, output_rate ] if model.to_s.match?(pattern)
    end
    DEFAULT_RATE
  end
end
