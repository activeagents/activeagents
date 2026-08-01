# frozen_string_literal: true

# Hosted-platform trace store, backed by the activeagent gem's telemetry
# implementation.
#
# All scopes (recent, with_errors, for_agent, for_service, for_date_range,
# for_account), the payload normalizer (.create_from_payload) and the
# instance helpers (root_span, llm_spans, tool_spans, provider, model,
# display_name, ...) are inherited from ActiveAgent::TelemetryTrace.
#
# The table (active_agent_telemetry_traces) is the same one a self-hosted
# install gets from the gem's dashboard install generator with
# --multi_tenant; the platform only layers on the mandatory account
# association and token-total dedup.
class TelemetryTrace < ActiveAgent::TelemetryTrace
  belongs_to :account

  validates :trace_id, uniqueness: { scope: :account_id }

  # WORKAROUND (redundant once activeagents/activeagent#344 ships, then
  # removable): the gem's telemetry instrumentation mirrors LLM token usage
  # onto both the llm span and the root span, and create_from_payload in
  # gem <= 1.0.3 sums tokens across all spans — which double-counts. When
  # child spans carry token data, recompute the denormalized totals from
  # child spans only. Idempotent alongside the fixed gem.
  def self.create_from_payload(trace, sdk_info = {}, account: nil)
    record = super
    record.send(:dedupe_token_totals!)
    record.send(:auto_register_agent!)
    record
  end

  private

  # Observed-agent registration: any agent that ships a trace appears in the
  # Agents view automatically — the agents table carries observed-identity
  # columns (service_name, agent_class_name, action_name + unique index) for
  # exactly this, but until now only external syncs populated them.
  # Registration must never break ingest, hence the blanket rescue.
  def auto_register_agent!
    return if agent_class.blank?

    user = account&.members&.order(:id)&.first
    return unless user

    action = agent_action.presence
    observed = Agent.find_or_initialize_by(
      user_id: user.id,
      service_name: service_name.presence || "unknown",
      agent_class_name: agent_class,
      action_name: action
    )
    if observed.new_record?
      observed.name = [ agent_class, action ].compact.join(".")
      observed.source = "telemetry"
      observed.status = :active
      observed.first_observed_at = created_at
    end
    observed.provider = provider if provider.present?
    observed.model = model if model.present?
    observed.last_observed_at = created_at
    observed.save!

    update_column(:agent_id, observed.id) if agent_id.nil?
    materialize_interaction!(observed)
  rescue StandardError => e
    Rails.logger.warn("[TelemetryTrace] agent auto-registration failed for #{trace_id}: #{e.class} #{e.message}")
  end

  # Traces carry the prompt/generation contents as span attributes; turn each
  # trace into an AgentContext (+ messages + generation) so observed agents'
  # activity shows in the Interactions view exactly like platform-run agents.
  def materialize_interaction!(observed)
    return if AgentContext.with_trace(trace_id).exists?

    prompt_attributes = (spans || []).find { |s| s["type"] == "prompt" }&.dig("attributes") || {}
    llm_attributes = llm_spans.first&.dig("attributes") || {}

    inbound = begin
      JSON.parse(prompt_attributes["prompt.input.messages"].to_s)
    rescue JSON::ParserError
      []
    end
    output = llm_attributes["llm.output.message"]
    return if inbound.blank? && output.blank? # trace predates content capture

    context = AgentContext.create!(
      contextable: observed,
      agent_name: agent_class,
      action_name: agent_action.presence || "unknown",
      instructions: prompt_attributes["prompt.input.instructions"],
      trace_id: trace_id,
      total_input_tokens: total_input_tokens.to_i,
      total_output_tokens: total_output_tokens.to_i
    )
    inbound.each do |message|
      next if message["content"].blank?

      context.messages.create!(role: message["role"].presence || "user", content: message["content"])
    end
    tool_spans.each do |span|
      span_attributes = span["attributes"] || {}
      result = span_attributes["tool.output.result"]
      next if result.blank?

      context.messages.create!(
        role: "tool",
        tool_name: span_attributes["tool.name"].presence || span["name"].to_s.delete_prefix("tool."),
        tool_arguments: parse_tool_arguments(span_attributes["tool.input.args"]),
        content: result,
        tool_result: result
      )
    end
    context.messages.create!(role: "assistant", content: output) if output.present?
    context.generations.create!(
      content: output,
      model: model,
      provider: provider,
      finish_reason: llm_attributes["llm.finish_reason"],
      input_tokens: total_input_tokens.to_i,
      output_tokens: total_output_tokens.to_i,
      duration_seconds: total_duration_ms.to_f / 1000.0,
      trace_id: trace_id
    )
  end

  def dedupe_token_totals!
    child_spans = (spans || []).reject { |s| s["parent_span_id"].nil? }
    return unless child_spans.any? { |s| span_token_sum(s).positive? }

    update_columns(
      total_input_tokens: child_spans.sum { |s| s.dig("tokens", "input").to_i },
      total_output_tokens: child_spans.sum { |s| s.dig("tokens", "output").to_i },
      total_thinking_tokens: child_spans.sum { |s| s.dig("tokens", "thinking").to_i }
    )
  end

  def span_token_sum(span)
    tokens = span["tokens"] || {}
    tokens["input"].to_i + tokens["output"].to_i + tokens["thinking"].to_i
  end

  def parse_tool_arguments(raw)
    return nil if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    { "raw" => raw }
  end
end
