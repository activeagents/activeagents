# frozen_string_literal: true

module Ragents
  module Providers
    # SimulatedProvider for benchmarking - Ractor-safe with configurable latency.
    #
    # Unlike MockProvider (scripted responses), SimulatedProvider simulates
    # real I/O latency and CPU work, making it suitable for concurrency benchmarks.
    #
    # ## Ruby 4.0 Ractor Safety
    #
    # This class is designed to be instantiated inside each Ractor.
    # All configuration is passed via the constructor and stored as instance vars.
    #
    class SimulatedProvider < BaseProvider
      DEFAULT_IO_MS = 100
      DEFAULT_CPU_ITERATIONS = 50_000

      def initialize(io_ms: DEFAULT_IO_MS, cpu_iterations: DEFAULT_CPU_ITERATIONS, default_model: "simulated-gpt")
        @io_seconds = io_ms / 1000.0
        @cpu_iterations = cpu_iterations
        @default_model = default_model.freeze
        freeze
      end

      def chat(messages:, tools: [], model: nil, **_opts)
        # Simulate network I/O
        # Use Async-compatible sleep if inside an Async context, otherwise regular sleep
        if defined?(Async::Task) && (task = Async::Task.current?)
          task.sleep(@io_seconds)
        else
          sleep @io_seconds
        end

        # Simulate CPU-bound response parsing (competes for GVL in Threads,
        # runs in parallel in Ractors)
        _sum = 0
        @cpu_iterations.times { |i| _sum += i * i }

        last_content = messages.last&.dig(:content) || ""
        content = "Simulated response for: #{last_content[0, 40]}"

        GenerationResult.new(
          content: content,
          tool_calls: [],
          input_tokens: 80 + rand(40),
          output_tokens: 15 + rand(20),
          model: @default_model,
          stop_reason: "end_turn"
        )
      end

      # Expose io_seconds for benchmark inspection
      attr_reader :io_seconds
    end
  end
end
