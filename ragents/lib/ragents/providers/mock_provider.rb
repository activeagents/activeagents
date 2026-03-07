# frozen_string_literal: true

module Ragents
  module Providers
    # MockProvider is used for testing and benchmarking.
    # It returns pre-scripted responses in sequence.
    #
    # ## Usage
    #
    #   provider = Ragents::Providers::MockProvider.new(
    #     responses: [
    #       { content: "Hello!" },
    #       { tool_calls: [{ id: "1", name: "search", arguments: { query: "Ruby" } }] },
    #       { content: "Here is what I found..." }
    #     ]
    #   )
    class MockProvider < BaseProvider
      def initialize(responses: [], default_model: "mock-model")
        @responses     = responses.dup
        @call_count    = 0
        @default_model = default_model.freeze
        # NOTE: MockProvider is NOT frozen because @call_count is mutable.
        # In Ractor usage, instantiate inside the Ractor.
      end

      def chat(messages:, tools: [], model: nil, **_opts)
        response_spec = @responses[@call_count % @responses.length] || { content: "Mock response" }
        @call_count += 1

        GenerationResult.new(
          content: response_spec[:content],
          tool_calls: response_spec[:tool_calls] || [],
          input_tokens: messages.sum { |m| (m[:content] || "").length / 4 },
          output_tokens: (response_spec[:content] || "").length / 4,
          model: @default_model,
          stop_reason: response_spec[:tool_calls]&.any? ? "tool_use" : "end_turn"
        )
      end

      attr_reader :call_count
    end
  end
end
