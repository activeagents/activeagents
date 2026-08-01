# frozen_string_literal: true

# Serializes TelemetryTrace records (gem span payloads) into the view-model
# consumed by the dashboard's TracesView: relative span offsets for the
# waterfall timeline, nesting depth, and token totals.
class TelemetryTraceSerializer
  # Span types understood by the dashboard timeline (superset of the gem's
  # ActiveAgent::Telemetry::Span::TYPES).
  KNOWN_SPAN_TYPES = %w[root prompt generate llm tool thinking embedding response error].freeze

  def self.summary(trace, generation: nil)
    new(trace, generation: generation).summary
  end

  def self.detail(trace)
    new(trace).detail
  end

  # generation is the AgentGeneration recorded under this trace_id, when
  # one exists. Passing it in lets the controller batch the lookup for a
  # whole list instead of querying per row.
  def initialize(trace, generation: nil)
    @trace = trace
    @generation = generation
  end

  def summary
    {
      id: @trace.id,
      trace_id: @trace.trace_id,
      short_id: @trace.trace_id&.first(8),
      agent: @trace.agent_class,
      action: @trace.agent_action,
      display_name: @trace.display_name,
      service_name: @trace.service_name,
      environment: @trace.environment,
      provider: @trace.provider,
      model: @trace.model,
      status: @trace.status,
      error: @trace.error_message,
      duration_ms: @trace.total_duration_ms&.to_f&.round(2),
      timestamp: @trace.timestamp&.iso8601(3),
      timestamp_ms: @trace.timestamp&.to_f&.*(1000)&.round,
      tokens: {
        input: @trace.total_input_tokens || 0,
        output: @trace.total_output_tokens || 0,
        thinking: @trace.total_thinking_tokens || 0,
        total: @trace.total_tokens
      },
      estimated_cost: ModelPricing.estimate(
        model: @trace.model,
        input_tokens: @trace.total_input_tokens,
        output_tokens: @trace.total_output_tokens
      ),
      context: context_summary,
      spans: serialized_spans
    }
  end

  def detail
    summary.merge(
      resource_attributes: @trace.resource_attributes,
      sdk_info: @trace.sdk_info,
      # The full per-source attribution costs a messages load, so it is
      # only built for the drilled-in trace. List rows get the measured
      # numbers from #context_summary instead.
      context: detail_generation ? ContextUtilization.for_generation(detail_generation) : context_summary
    )
  end

  private

  # Context occupancy at the moment of the call. The generation's
  # input_tokens is exactly what the provider read, so nothing here is
  # inferred — only the denominator is resolved, and window_known says
  # whether it was looked up or assumed.
  #
  # Falls back to the trace's own token totals when no AgentGeneration was
  # recorded under this trace_id (traces from the gem's own runs).
  def context_summary
    model = @generation&.model || @trace.model
    used = @generation ? @generation.input_tokens.to_i : @trace.total_input_tokens.to_i
    return nil if used.zero?

    limit = ModelContextWindow.for(model)
    pct = ContextUtilization.percent_of(used, limit)

    {
      model: model,
      limit: limit,
      window_known: ModelContextWindow.known?(model),
      used: used,
      free: [ limit - used, 0 ].max,
      overflow: [ used - limit, 0 ].max,
      pct: pct,
      state: ContextUtilization.state_for(pct),
      measured: true,
      cached: @generation&.cached_tokens.to_i,
      thinking: (@generation&.reasoning_tokens || @trace.total_thinking_tokens).to_i,
      finish_reason: @generation&.finish_reason,
      truncated: @generation&.truncated? || false
    }
  end

  def detail_generation
    @detail_generation ||= @generation || AgentGeneration.with_trace(@trace.trace_id).order(:created_at).last
  end

  # Maps raw gem spans (start_time/end_time ISO strings, parent_span_id
  # links) to waterfall rows with millisecond offsets relative to the root
  # span and a nesting depth.
  def serialized_spans
    spans = Array(@trace.spans)
    return [] if spans.empty?

    by_id = spans.index_by { |s| s["span_id"] }
    root = spans.find { |s| s["parent_span_id"].nil? } || spans.first
    root_start = parse_time(root["start_time"])

    spans.map do |span|
      start = parse_time(span["start_time"])
      offset = (root_start && start) ? ((start - root_start) * 1000).round(2) : 0

      {
        span_id: span["span_id"],
        name: span["name"],
        type: normalized_type(span),
        start: [ offset, 0 ].max,
        duration: span["duration_ms"]&.to_f&.round(2) || 0,
        nested: depth_of(span, by_id),
        status: span["status"],
        error: span["status"] == "ERROR",
        tokens: span["tokens"],
        attributes: span["attributes"]
      }
    end
  end

  def normalized_type(span)
    type = span["type"].to_s
    KNOWN_SPAN_TYPES.include?(type) ? type : "root"
  end

  def depth_of(span, by_id)
    depth = 0
    current = span
    while (parent_id = current["parent_span_id"])
      parent = by_id[parent_id]
      break unless parent

      depth += 1
      current = parent
      break if depth > 10
    end
    depth
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
