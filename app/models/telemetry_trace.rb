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

  # The gem's telemetry instrumentation mirrors LLM token usage onto both the
  # llm span and the root span, and create_from_payload sums tokens across
  # all spans — which double-counts. When child spans carry token data,
  # recompute the denormalized totals from child spans only.
  def self.create_from_payload(trace, sdk_info = {}, account: nil)
    record = super
    record.send(:dedupe_token_totals!)
    record
  end

  private

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
end
