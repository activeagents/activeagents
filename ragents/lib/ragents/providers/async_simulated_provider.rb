# frozen_string_literal: true

module Ragents
  module Providers
    # AsyncSimulatedProvider for benchmarking with Async fiber scheduler.
    #
    # This provider uses Async::Task.current.sleep instead of Kernel#sleep,
    # allowing the fiber scheduler to properly yield during I/O simulation.
    #
    # For non-Async contexts, falls back to regular sleep.
    #
    class AsyncSimulatedProvider < BaseProvider
      DEFAULT_IO_MS = 100
      DEFAULT_CPU_ITERATIONS = 50_000

      def initialize(io_ms: DEFAULT_IO_MS, cpu_iterations: DEFAULT_CPU_ITERATIONS, default_model: "async-simulated-gpt")
        @io_seconds = io_ms / 1000.0
        @cpu_iterations = cpu_iterations
        @default_model = default_model.freeze
        freeze
      end

      def chat(messages:, tools: [], model: nil, **_opts)
        # Use Async-compatible sleep if running inside an Async context
        if defined?(Async::Task) && Async::Task.current?
          Async::Task.current.sleep(@io_seconds)
        else
          sleep @io_seconds
        end

        # Simulate CPU-bound response parsing
        _sum = 0
        @cpu_iterations.times { |i| _sum += i * i }

        last_content = messages.last&.dig(:content) || ""
        content = "Async simulated response for: #{last_content[0, 40]}"

        GenerationResult.new(
          content: content,
          tool_calls: [],
          input_tokens: 80 + rand(40),
          output_tokens: 15 + rand(20),
          model: @default_model,
          stop_reason: "end_turn"
        )
      end
    end
  end
end
