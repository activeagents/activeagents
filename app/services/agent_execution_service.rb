# frozen_string_literal: true

# Executes a dashboard-configured Agent through the activeagent gem and
# records a telemetry trace for the run.
#
# The requested provider is used when its credentials are configured in
# config/active_agent.yml; otherwise execution falls back to the gem's mock
# provider so the full prompt -> provider -> response pipeline (including
# usage accounting) still runs without external API keys.
#
# Traces are built with the gem's ActiveAgent::Telemetry::Span and persisted
# through TelemetryTrace.create_from_payload — the same normalizer used by
# the telemetry ingest endpoint — so platform-executed runs and SDK-reported
# runs share one pipeline.
class AgentExecutionService
  SERVICE_NAME = "activeagents-platform"

  def self.call(agent_record, run)
    new(agent_record, run).call
  end

  def initialize(agent_record, run)
    @agent_record = agent_record
    @run = run
  end

  def call
    root_span = build_root_span
    llm_span = root_span.add_span(
      "llm.generate",
      span_type: :llm,
      "llm.provider" => provider.to_s,
      "llm.model" => model
    )

    begin
      response = generate!
      usage = response.usage
      input = usage&.input_tokens.to_i
      output = usage&.output_tokens.to_i
      thinking = usage&.reasoning_tokens.to_i

      llm_span.set_tokens(input: input, output: output, thinking: thinking)
      llm_span.finish
      root_span.finish

      {
        output: response.message&.content,
        metadata: {
          provider: provider.to_s,
          model: model,
          requested_provider: @agent_record.provider,
          mock: mock_fallback?,
          trace_id: root_span.trace_id,
          context_id: conversation_context&.id
        },
        usage: {
          input_tokens: input,
          output_tokens: output,
          total_tokens: usage&.total_tokens || input + output + thinking
        }
      }
    rescue StandardError => e
      llm_span.record_error(e)
      llm_span.finish
      root_span.record_error(e)
      root_span.finish
      raise
    ensure
      record_trace(root_span)
    end
  end

  # Returns the provider actually used for this execution.
  def provider
    @provider ||= provider_available?(@agent_record.provider) ? @agent_record.provider.to_sym : :mock
  end

  def mock_fallback?
    provider == :mock && @agent_record.provider != "mock"
  end

  private

  def model
    mock_fallback? ? "mock-#{@agent_record.model}" : @agent_record.model
  end

  def generate!
    effective_provider = provider
    provider_model = @agent_record.model
    model_options = @agent_record.model_config.to_h.symbolize_keys.slice(:temperature, :max_tokens, :top_p)
    klass_name = agent_class_name
    agent_record = @agent_record
    input = @run.input_prompt
    instructions = @agent_record.instructions
    run_trace_id = trace_id

    agent_class = Class.new(ActiveAgent::Base) do
      # SolidAgent persists contexts under self.class.name; anonymous
      # classes would fail its agent_name presence validation.
      define_singleton_method(:name) { klass_name }

      # Persist the conversation (agent_contexts / agent_messages /
      # agent_generations) via solid_agent. contextual: false — the context
      # is loaded explicitly in the action below.
      include SolidAgent::HasContext
      has_context contextual: false

      if effective_provider == :mock
        generate_with :mock
      else
        generate_with effective_provider, model: provider_model, **model_options
      end

      define_method :ask do
        # Thread the run's telemetry trace_id through prompt_options so
        # SolidAgent's provenance (and AgentContext#record_generation_with_
        # provenance!) can correlate the persisted generation with its trace.
        prompt_options[:trace_id] = run_trace_id
        load_context(contextable: agent_record)

        options = { message: input }
        options[:instructions] = instructions if instructions.present?
        prompt(**options)
      end
    end

    agent_class.ask.generate_now
  end

  def provider_available?(name)
    return true if name.to_s == "mock"

    config = ActiveAgent.configuration[name.to_sym]
    return false unless config.respond_to?(:[])

    if name.to_s == "ollama"
      config[:host].present?
    else
      config[:access_token].present?
    end
  rescue StandardError
    false
  end

  def build_root_span
    ActiveAgent::Telemetry::Span.new(
      "#{agent_class_name}.prompt",
      trace_id: trace_id,
      span_type: :root,
      "agent.class" => agent_class_name,
      "agent.action" => "prompt",
      "agent.provider" => provider.to_s,
      "agent.model" => model,
      "service.name" => SERVICE_NAME,
      "service.environment" => Rails.env,
      "telemetry.sdk.name" => "activeagent",
      "telemetry.sdk.version" => ActiveAgent::VERSION
    )
  end

  def agent_class_name
    base = @agent_record.agent_class_name.presence || @agent_record.name.parameterize(separator: "_").camelize
    base.end_with?("Agent") ? base : "#{base}Agent"
  end

  # Reuse the run's trace_id so AgentRun and TelemetryTrace correlate.
  def trace_id
    @trace_id ||= @run.trace_id.presence || SecureRandom.hex(16)
  end

  # The solid_agent conversation context this execution persisted into
  # (one per agent + action on this platform).
  def conversation_context
    AgentContext.find_by(contextable: @agent_record, agent_name: agent_class_name, action_name: "ask")
  end

  def account
    @account ||= @agent_record.user&.primary_account
  end

  def record_trace(root_span)
    return unless account

    payload = {
      trace_id: root_span.trace_id,
      service_name: SERVICE_NAME,
      environment: Rails.env,
      timestamp: Time.current.iso8601(6),
      resource_attributes: { "platform.agent_id" => @agent_record.id, "platform.run_id" => @run.id },
      spans: flatten_spans(root_span)
    }.as_json

    sdk_info = {
      name: "activeagent",
      version: ActiveAgent::VERSION,
      language: "ruby",
      runtime_version: RUBY_VERSION
    }.as_json

    return if TelemetryTrace.for_account(account).exists?(trace_id: root_span.trace_id)

    TelemetryTrace.create_from_payload(payload, sdk_info, account: account)
  rescue StandardError => e
    Rails.logger.error("[AgentExecutionService] Failed to record trace #{root_span.trace_id}: #{e.class} - #{e.message}")
    nil
  end

  # Flattens the span hierarchy the same way the gem's Tracer does before
  # reporting (children stripped, parent_span_id links preserved).
  def flatten_spans(span)
    result = [ span.to_h.except(:children) ]
    span.children.each { |child| result.concat(flatten_spans(child)) }
    result
  end
end
