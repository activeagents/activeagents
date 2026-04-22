# frozen_string_literal: true

require "ragents"

# BenchmarkRunnerService
#
# Runs ragents concurrency benchmarks within the Rails application context.
# Results can be stored locally or posted to the /api/benchmarks endpoint.
#
# Usage:
#   service = BenchmarkRunnerService.new(requests: 10, provider: "mock")
#   results = service.run
#
class BenchmarkRunnerService
  require "etc"

  PROVIDERS = {
    "mock" => ->(opts) {
      [ Ragents::Providers::SimulatedProvider, { io_ms: opts[:io_ms], cpu_iterations: opts[:cpu_iters] } ]
    },
    "realistic" => ->(opts) {
      [ Ragents::Providers::RealisticLLMProvider, {
        median_latency_ms: opts[:median_latency] || 3000,
        latency_sigma: opts[:latency_sigma] || 0.8,
        token_rate_range: 30..100,
        response_length_range: 50..500,
        cpu_work_per_token: 100
      } ]
    },
    "openai" => ->(_opts) {
      [ Ragents::Providers::OpenAIProvider, { api_key: ENV.fetch("OPENAI_API_KEY", "") } ]
    },
    "anthropic" => ->(_opts) {
      [ Ragents::Providers::AnthropicProvider, { api_key: ENV.fetch("ANTHROPIC_API_KEY", "") } ]
    }
  }.freeze

  DEFAULT_OPTIONS = {
    requests: 10,
    io_ms: 100,
    cpu_iters: 50_000,
    context_kb: 0,
    provider: "mock",
    pool_size: nil,
    include_ractors: true
  }.freeze

  def initialize(**options)
    @options = DEFAULT_OPTIONS.merge(options)
    @n = @options[:requests]
    @io_ms = @options[:io_ms]
    @cpu_iters = @options[:cpu_iters]
    @context_kb = @options[:context_kb]
    @pool_size = @options[:pool_size] || [ cpu_cores, @n ].min

    provider_builder = PROVIDERS[@options[:provider]] || PROVIDERS["mock"]
    @provider_class, @provider_opts = provider_builder.call(@options)

    @inputs = @n.times.map { |i| "Request #{i + 1}: Explain #{%w[Ractors fibers threads async parallelism][i % 5]} in Ruby." }.freeze
    @system = "You are a concise Ruby expert."
  end

  def run
    run_at = Time.current.iso8601
    strategies = run_benchmarks

    {
      run_at: run_at,
      hardware: hardware_info,
      config: config_info,
      strategies: strategies,
      winner: strategies.min_by { |s| s[:wall_time_ms] }&.slice(:name, :throughput, :wall_time_ms)
    }
  end

  private

  def cpu_cores
    @cpu_cores ||= Etc.nprocessors rescue 4
  end

  def hardware_info
    {
      ruby_version: RUBY_VERSION,
      platform: RUBY_PLATFORM,
      cpu_cores: cpu_cores,
      cpu_model: RbConfig::CONFIG["host_cpu"],
      rails_env: Rails.env
    }
  end

  def config_info
    {
      n_requests: @n,
      io_latency_ms: @io_ms,
      cpu_iterations: @cpu_iters,
      context_kb: @context_kb,
      pool_size: @pool_size,
      provider: @options[:provider]
    }
  end

  def run_benchmarks
    strategies = []

    # 1. Sequential
    strategies << bench_strategy("Sequential", @n) do
      @inputs.map { |input| run_agent(input) }
    end

    sequential_ms = strategies.first[:wall_time_ms]

    # 2. Threads (unbounded)
    strategies << bench_strategy("Threads (N=#{@n})", @n) do
      threads = @inputs.map { |input| Thread.new { run_agent(input) } }
      threads.map(&:value)
    end

    # 3. Thread Pool (bounded)
    strategies << bench_strategy("Thread Pool (size=#{@pool_size})", @n) do
      require "thread"
      results = Array.new(@n)
      queue = Queue.new
      @inputs.each_with_index { |input, idx| queue << [ input, idx ] }
      @pool_size.times { queue << nil }

      workers = @pool_size.times.map do
        Thread.new do
          while (item = queue.pop)
            input, idx = item
            results[idx] = run_agent(input)
          end
        end
      end
      workers.each(&:join)
      results
    end

    # 4. Ractors (only if enabled - may crash on some Ruby versions)
    if @options[:include_ractors]
      begin
        strategies << bench_strategy("Ractors (N=#{@n})", @n) do
          pool = Ragents::Ractor::AgentPool.new(
            size: @n,
            provider_class: @provider_class,
            provider_opts: @provider_opts,
            system_prompt: @system
          )
          results = pool.process(@inputs)
          results.map do |r|
            if r.is_a?(Ragents::Ractor::FailedResult)
              { error: r.content, duration_ms: 0, context_bytes: 0 }
            else
              { result: r, duration_ms: 0, context_bytes: 0 }
            end
          end
        end

        # 5. Ractor Pool (bounded)
        strategies << bench_strategy("Ractor Pool (size=#{@pool_size})", @n) do
          pool = Ragents::Ractor::AgentPool.new(
            size: @pool_size,
            provider_class: @provider_class,
            provider_opts: @provider_opts,
            system_prompt: @system
          )
          results = pool.process(@inputs)
          results.map do |r|
            if r.is_a?(Ragents::Ractor::FailedResult)
              { error: r.content, duration_ms: 0, context_bytes: 0 }
            else
              { result: r, duration_ms: 0, context_bytes: 0 }
            end
          end
        end
      rescue => e
        Rails.logger.warn "Ractor benchmarks failed: #{e.message}"
      end
    end

    # Add speedup ratios
    strategies.each do |s|
      s[:speedup_vs_sequential] = (sequential_ms / s[:wall_time_ms]).round(2)
    end

    strategies
  end

  # Direct provider call for sequential/thread benchmarks (no Ractors)
  # This avoids Ractor overhead for non-Ractor strategies and works in
  # environments where Ractors may not be supported (like Cloud Run).
  def run_agent(input)
    provider = @provider_class.new(**@provider_opts)
    messages = [
      { role: "system", content: @system },
      { role: "user", content: input }
    ]

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    gen_result = provider.chat(messages: messages)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - start

    # Wrap in a struct-like object that matches RunResult interface
    result = Ragents::Ractor::RunResult.new(
      assistant_message: Ragents::AssistantMessage.new(
        content: gen_result.content,
        input_tokens: gen_result.input_tokens,
        output_tokens: gen_result.output_tokens,
        model: gen_result.model
      ),
      context_snapshot: [].freeze
    )
    { result: result, duration_ms: elapsed, context_bytes: 0 }
  rescue => e
    { error: "Error: #{e.class}: #{e.message}", duration_ms: 0, context_bytes: 0 }
  end

  def bench_strategy(name, n)
    mem_before = memory_mb
    gc_before = GC.count

    wall_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    results = yield
    wall_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall_start) * 1000).round(1)

    gc_after = GC.count
    mem_after = memory_mb

    durations = results.map { |r| r[:duration_ms] }
    errors = results.count { |r| r[:error] }
    tokens_in = results.sum { |r| r[:result]&.assistant_message&.input_tokens.to_i }
    tokens_out = results.sum { |r| r[:result]&.assistant_message&.output_tokens.to_i }

    request_details = results.each_with_index.map do |r, idx|
      {
        request_id: idx + 1,
        duration_ms: r[:duration_ms],
        input_tokens: r[:result]&.assistant_message&.input_tokens.to_i,
        output_tokens: r[:result]&.assistant_message&.output_tokens.to_i,
        total_tokens: r[:result]&.assistant_message&.input_tokens.to_i + r[:result]&.assistant_message&.output_tokens.to_i,
        context_bytes: r[:context_bytes].to_i,
        error: r[:error],
        content_preview: r[:result]&.assistant_message&.content&.to_s&.slice(0, 100)
      }
    end

    {
      name: name,
      n_requests: n,
      wall_time_ms: wall_ms,
      throughput: (n / (wall_ms / 1000.0)).round(2),
      avg_latency_ms: durations.any? ? durations.sum.to_f / durations.size : 0,
      min_latency_ms: durations.min || 0,
      max_latency_ms: durations.max || 0,
      p50_latency_ms: percentile(durations, 50),
      p95_latency_ms: percentile(durations, 95),
      errors: errors,
      total_input_tokens: tokens_in,
      total_output_tokens: tokens_out,
      memory_mb_before: mem_before,
      memory_mb_after: mem_after,
      memory_delta_mb: (mem_after - mem_before).round(1),
      gc_runs: gc_after - gc_before,
      context_allocated_mb: 0.0,
      requests: request_details
    }
  end

  def percentile(arr, pct)
    return 0 if arr.empty?
    sorted = arr.sort
    idx = ((pct / 100.0) * (sorted.size - 1)).round
    sorted[idx] || 0
  end

  def memory_mb
    (`ps -o rss= -p #{Process.pid}`.to_i / 1024.0).round(1)
  rescue
    0.0
  end
end
