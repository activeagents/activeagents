# frozen_string_literal: true

module Ragents
  module Ractor
    # AgentPool manages a fixed-size pool of reusable AgentRactors.
    #
    # ## Why a Pool?
    #
    # Spawning a Ractor has a one-time cost (stack allocation, object space
    # initialisation).  For high-throughput workloads — e.g. processing thousands
    # of user messages — reusing Ractors across requests eliminates this overhead.
    #
    # ## Design
    #
    # Each pool slot holds one AgentRactor configuration.  Requests are
    # dispatched round-robin (or can be load-balanced by queue depth in a
    # future version).  The pool itself coordinates via a Queue (thread-safe,
    # GVL-friendly) rather than another Ractor to avoid over-engineering.
    #
    # ## Usage
    #
    #   pool = Ragents::Ractor::AgentPool.new(
    #     size: 4,
    #     provider_class: Ragents::Providers::OpenAIProvider,
    #     provider_opts: { api_key: ENV["OPENAI_API_KEY"] },
    #     system_prompt: "You are a helpful assistant"
    #   )
    #
    #   results = pool.process(["Question 1", "Question 2", "Question 3"])
    #   results.each { |r| puts r.content }
    #
    #   pool.shutdown

    class AgentPool
      # @param size [Integer] number of worker slots (one Ractor per request)
      # @param **agent_opts forwarded to AgentRactor.new
      def initialize(size: 4, **agent_opts)
        @size       = size
        @agent_opts = agent_opts.freeze
        @queue      = Queue.new
        @shutdown   = false
      end

      # Process a list of inputs concurrently using up to @size parallel Ractors.
      # Blocks until all inputs are processed.
      #
      # @param inputs [Array<String>]
      # @param context_snapshot [Array<Message>, nil]
      # @return [Array<RunResult>] in same order as inputs
      def process(inputs, context_snapshot: nil)
        return [] if inputs.empty?

        results  = Array.new(inputs.size)
        semaphore = SizedQueue.new(@size)

        threads = inputs.each_with_index.map do |input, idx|
          semaphore.push(:token)  # blocks when pool is full
          Thread.new do
            agent = AgentRactor.new(**@agent_opts)
            results[idx] = agent.run(input, context_snapshot: context_snapshot)
          rescue StandardError => e
            results[idx] = FailedResult.new(error: e)
          ensure
            semaphore.pop
          end
        end

        threads.each(&:join)
        results
      end

      # Process inputs as a lazy stream, yielding results as they complete
      # (not necessarily in order).
      #
      # @param inputs [Array<String>]
      # @yield [index, RunResult]
      def process_stream(inputs, context_snapshot: nil)
        return enum_for(:process_stream, inputs, context_snapshot: context_snapshot) unless block_given?

        semaphore = SizedQueue.new(@size)
        mutex     = Mutex.new
        completed = Queue.new

        threads = inputs.each_with_index.map do |input, idx|
          semaphore.push(:token)
          Thread.new do
            agent  = AgentRactor.new(**@agent_opts)
            result = agent.run(input, context_snapshot: context_snapshot)
            completed.push([idx, result])
          rescue StandardError => e
            completed.push([idx, FailedResult.new(error: e)])
          ensure
            semaphore.pop
          end
        end

        inputs.size.times do
          idx, result = completed.pop
          yield idx, result
        end

        threads.each(&:join)
      end

      # Placeholder for clean shutdown (future: drain in-flight requests)
      def shutdown
        @shutdown = true
      end
    end

    # Returned by AgentPool when a slot raises an unhandled exception.
    FailedResult = Data.define(:error) do
      def content = "Error: #{error.message}"
      def context_snapshot = [].freeze
      def success? = false
    end
  end
end
