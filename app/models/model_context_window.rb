# frozen_string_literal: true

# Resolves a model's context window — the total tokens a provider will hold
# in one request — so context-utilization views can express occupancy as a
# share of what the model can actually take.
#
# Resolution order mirrors ModelPricing: RubyLLM's model registry first
# (maintained upstream per model), then a static pattern table for aliases
# and self-hosted models the registry doesn't know, then a conservative
# default. Windows are the provider's advertised limit; opt-in beta headers
# that extend it (Anthropic's 1M context) are not modeled, so a run using
# one reads pessimistically rather than silently over-full.
#
# `known?` reports whether the window was resolved or defaulted, so the UI
# can mark an assumed denominator instead of presenting a guess as fact.
class ModelContextWindow
  # [pattern, window tokens] — first match wins, so specific ids come first.
  WINDOWS = [
    [ /gpt-4o/i, 128_000 ],
    [ /gpt-4\.1/i, 1_047_576 ],
    [ /gpt-5/i, 400_000 ],
    [ /o3|o4-mini/i, 200_000 ],
    [ /gpt-4-turbo/i, 128_000 ],
    [ /gpt-4-32k/i, 32_768 ],
    [ /gpt-4/i, 8_192 ],
    [ /gpt-3\.5/i, 16_385 ],
    [ /claude.*(fable|mythos)/i, 200_000 ],
    [ /claude.*(opus|sonnet|haiku)/i, 200_000 ],
    [ /claude/i, 200_000 ],
    [ /gemini.*(1\.5|2\.5).*pro/i, 2_097_152 ],
    [ /gemini/i, 1_048_576 ],
    [ /llama-?3\.[1-3]|llama-?4/i, 128_000 ],
    [ /llama/i, 8_192 ],
    [ /qwen3/i, 32_768 ],
    [ /mixtral|mistral/i, 32_768 ],
    [ /deepseek/i, 65_536 ],
    [ /mock/i, 128_000 ]
  ].freeze

  # Used when nothing matches. 128k is the modern median; a too-large
  # default would hide pressure, which is the failure mode that matters
  # here, so this errs small.
  DEFAULT_WINDOW = 128_000

  # @return [Integer] context window in tokens
  def self.for(model)
    return DEFAULT_WINDOW if model.blank?

    registry_window(model) || static_window(model) || DEFAULT_WINDOW
  end

  # @return [Boolean] false when `for` fell through to DEFAULT_WINDOW
  def self.known?(model)
    return false if model.blank?

    !(registry_window(model) || static_window(model)).nil?
  end

  # Exact per-model windows from RubyLLM's registry. Memoized — the
  # registry scan is not free and serialization calls this per row.
  def self.registry_window(model)
    @registry_windows ||= {}
    return @registry_windows[model] if @registry_windows.key?(model)

    @registry_windows[model] = begin
      window = RubyLLM.models.find(model.to_s)&.context_window
      window if window.to_i.positive?
    rescue StandardError
      nil
    end
  end

  def self.static_window(model)
    WINDOWS.each do |pattern, window|
      return window if model.to_s.match?(pattern)
    end
    nil
  end
end
