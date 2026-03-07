# frozen_string_literal: true

module Ragents
  module Providers
    # RealisticLLMProvider simulates real-world LLM API behavior for benchmarking.
    #
    # Real LLM calls have these characteristics:
    # - Response times follow a log-normal distribution (most fast, some slow)
    # - Token generation rate varies (30-100 tokens/sec)
    # - Response length varies based on prompt complexity
    # - CPU work for parsing scales with response size
    #
    # ## Distribution Parameters
    #
    # Response times are modeled as log-normal with:
    # - Median: ~3 seconds (typical GPT-4 response)
    # - 90th percentile: ~10 seconds
    # - 99th percentile: ~25 seconds
    # - Max clipped at 30 seconds
    #
    # ## Usage
    #
    #   provider = Ragents::Providers::RealisticLLMProvider.new(
    #     median_latency_ms: 3000,    # 3 second median
    #     latency_sigma: 0.8,         # log-normal spread
    #     token_rate_range: 30..100,  # tokens per second
    #     response_length_range: 50..500  # output tokens
    #   )
    #
    class RealisticLLMProvider < BaseProvider
      DEFAULT_MEDIAN_LATENCY_MS = 3000
      DEFAULT_SIGMA = 0.8  # log-normal sigma (higher = more variance)
      DEFAULT_TOKEN_RATE_RANGE = (30..100).freeze
      DEFAULT_RESPONSE_LENGTH_RANGE = (50..500).freeze
      MAX_LATENCY_MS = 30_000  # 30 second cap

      def initialize(
        median_latency_ms: DEFAULT_MEDIAN_LATENCY_MS,
        latency_sigma: DEFAULT_SIGMA,
        token_rate_range: DEFAULT_TOKEN_RATE_RANGE,
        response_length_range: DEFAULT_RESPONSE_LENGTH_RANGE,
        cpu_work_per_token: 100,  # iterations per output token
        default_model: "realistic-gpt-4"
      )
        @median_latency_ms = median_latency_ms
        @latency_sigma = latency_sigma
        @token_rate_range = token_rate_range
        @response_length_range = response_length_range
        @cpu_work_per_token = cpu_work_per_token
        @default_model = default_model.freeze

        # Pre-compute log-normal mu from median
        # For log-normal: median = e^mu, so mu = ln(median)
        @latency_mu = Math.log(@median_latency_ms)

        # Thread-safe random for Ractor compatibility
        @seed = Random.new_seed
      end

      def chat(messages:, tools: [], model: nil, **_opts)
        rng = Random.new(@seed ^ Thread.current.object_id ^ Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond))

        # Calculate input tokens from messages
        input_tokens = messages.sum { |m| estimate_tokens(m[:content] || "") }

        # Generate response length (longer prompts tend to get longer responses)
        base_length = rng.rand(@response_length_range)
        complexity_factor = 1.0 + (input_tokens / 500.0) * 0.5  # up to 50% longer for complex prompts
        output_tokens = (base_length * complexity_factor).to_i.clamp(@response_length_range.min, @response_length_range.max * 2)

        # Calculate token generation rate for this request
        token_rate = rng.rand(@token_rate_range)  # tokens per second

        # Calculate base latency from token rate
        generation_time_ms = (output_tokens / token_rate.to_f) * 1000

        # Add network/queue latency using log-normal distribution
        # Box-Muller transform for normal distribution
        u1 = rng.rand
        u2 = rng.rand
        z = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
        network_latency_ms = Math.exp(@latency_mu + @latency_sigma * z)

        # Total latency = generation time + network overhead
        total_latency_ms = (generation_time_ms + network_latency_ms).clamp(100, MAX_LATENCY_MS)

        # Simulate the wait (I/O bound)
        sleep(total_latency_ms / 1000.0)

        # Simulate CPU work for parsing/processing (scales with response size)
        cpu_iterations = output_tokens * @cpu_work_per_token
        _x = 0
        cpu_iterations.times { |i| _x += i * i }

        # Generate realistic-looking response content
        content = generate_response_content(messages, output_tokens, rng)

        GenerationResult.new(
          content: content,
          tool_calls: [],
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          model: @default_model,
          stop_reason: "end_turn",
          # Include timing metadata for analysis
          metadata: {
            simulated_latency_ms: total_latency_ms.round(1),
            token_rate: token_rate,
            generation_time_ms: generation_time_ms.round(1),
            network_latency_ms: network_latency_ms.round(1)
          }
        )
      end

      private

      def estimate_tokens(text)
        # Rough estimate: ~4 characters per token for English
        (text.to_s.length / 4.0).ceil.clamp(1, 100_000)
      end

      def generate_response_content(messages, target_tokens, rng)
        # Extract the last user message for context
        last_message = messages.reverse.find { |m| m[:role] == "user" }&.dig(:content) || "query"
        topic = last_message[0, 50].gsub(/[^a-zA-Z0-9\s]/, "")

        # Generate filler content that looks like an LLM response
        words = %w[
          the a an is are was were be been being have has had do does did
          will would could should may might must shall can
          and but or nor for yet so because although while if when where
          this that these those which what who whom whose
          very much many more most some any all both each every few
          Ruby Ractor thread fiber async concurrent parallel process
          agent LLM token context prompt response generation model
          performance latency throughput optimization efficiency
        ]

        # Build response with ~4 chars per token
        target_chars = target_tokens * 4
        response_parts = [ "Regarding #{topic}:" ]

        while response_parts.join(" ").length < target_chars
          sentence_length = rng.rand(8..20)
          sentence = sentence_length.times.map { words.sample(random: rng) }.join(" ")
          response_parts << sentence.capitalize + "."
        end

        response_parts.join(" ")[0, target_chars]
      end
    end
  end
end
