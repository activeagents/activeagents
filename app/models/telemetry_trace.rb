# frozen_string_literal: true

# Stores telemetry traces from ActiveAgent clients.
#
# This model extends the base functionality from ActiveAgent::TelemetryTrace
# (provided by the activeagent gem) with multi-tenant support for the
# activeagents.ai platform.
#
# Each trace represents a complete generation lifecycle, including prompt
# preparation, LLM calls, tool invocations, and error handling.
#
# @example Creating a trace from ingested data
#   TelemetryTrace.create_from_payload(trace_payload, sdk_info, account: account)
#
class TelemetryTrace < ApplicationRecord
  belongs_to :account

  # Status values for traces (shared with gem)
  STATUS_OK = "OK"
  STATUS_ERROR = "ERROR"
  STATUS_UNSET = "UNSET"

  validates :trace_id, presence: true

  # Scopes (extended from gem with multi-tenant support)
  scope :recent, -> { order(timestamp: :desc) }
  scope :with_errors, -> { where(status: STATUS_ERROR) }
  scope :for_service, ->(name) { where(service_name: name) }
  scope :for_environment, ->(env) { where(environment: env) }
  scope :for_agent, ->(agent_class) { where(agent_class: agent_class) }
  scope :for_date_range, ->(start_date, end_date) { where(timestamp: start_date..end_date) }
  scope :for_account, ->(account) { where(account: account) }

  # Creates a TelemetryTrace from an ingested trace payload.
  #
  # Uses the same signature as ActiveAgent::TelemetryTrace.create_from_payload
  # for consistency with the gem's interface.
  #
  # @param trace [Hash] The trace payload from ActiveAgent::Telemetry
  # @param sdk_info [Hash] SDK metadata
  # @param account [Account] The account that owns this trace (required in multi-tenant mode)
  # @return [TelemetryTrace] The created trace
  def self.create_from_payload(trace, sdk_info = {}, account: nil)
    spans = trace["spans"] || []
    root_span = spans.find { |s| s["parent_span_id"].nil? } || spans.first || {}

    # Calculate totals from all spans
    total_duration = root_span["duration_ms"]
    total_input = 0
    total_output = 0
    total_thinking = 0

    spans.each do |span|
      tokens = span["tokens"] || {}
      total_input += (tokens["input"] || 0)
      total_output += (tokens["output"] || 0)
      total_thinking += (tokens["thinking"] || 0)
    end

    # Extract agent info from root span attributes
    attributes = root_span["attributes"] || {}
    agent_class = attributes["agent.class"]
    agent_action = attributes["agent.action"]

    # Find any error message
    error_span = spans.find { |s| s["status"] == STATUS_ERROR }
    error_message = error_span&.dig("attributes", "error.message")

    create!(
      account: account,
      trace_id: trace["trace_id"],
      service_name: trace["service_name"],
      environment: trace["environment"],
      timestamp: Time.parse(trace["timestamp"]),
      spans: spans,
      resource_attributes: trace["resource_attributes"],
      sdk_info: sdk_info,
      total_duration_ms: total_duration,
      total_input_tokens: total_input,
      total_output_tokens: total_output,
      total_thinking_tokens: total_thinking,
      status: root_span["status"] || STATUS_UNSET,
      agent_class: agent_class,
      agent_action: agent_action,
      error_message: error_message
    )
  end

  # Returns the root span of this trace.
  #
  # @return [Hash, nil] The root span or nil
  def root_span
    spans&.find { |s| s["parent_span_id"].nil? }
  end

  # Returns all LLM spans in this trace.
  #
  # @return [Array<Hash>] LLM spans
  def llm_spans
    spans&.select { |s| s["type"] == "llm" } || []
  end

  # Returns all tool call spans in this trace.
  #
  # @return [Array<Hash>] Tool spans
  def tool_spans
    spans&.select { |s| s["type"] == "tool" } || []
  end

  # Returns total token count.
  #
  # @return [Integer] Total tokens used
  def total_tokens
    (total_input_tokens || 0) + (total_output_tokens || 0) + (total_thinking_tokens || 0)
  end

  # Returns whether this trace had an error.
  #
  # @return [Boolean]
  def error?
    status == STATUS_ERROR
  end

  # Returns display name for the trace.
  #
  # @return [String] Display name (e.g., "WeatherAgent.forecast")
  def display_name
    if agent_class && agent_action
      "#{agent_class}.#{agent_action}"
    elsif agent_class
      agent_class
    else
      trace_id&.first(8)
    end
  end

  # Returns formatted duration (from gem interface).
  #
  # @return [String] Duration in ms or s
  def formatted_duration
    return "—" unless total_duration_ms

    if total_duration_ms >= 1000
      "#{(total_duration_ms / 1000.0).round(2)}s"
    else
      "#{total_duration_ms.round(0)}ms"
    end
  end

  # Returns formatted token count (from gem interface).
  #
  # @return [String] Token count with K suffix for large numbers
  def formatted_tokens
    count = total_tokens
    return "0" if count.zero?

    if count >= 1000
      "#{(count / 1000.0).round(1)}K"
    else
      count.to_s
    end
  end

  # Returns the provider used (from LLM spans).
  #
  # @return [String, nil] Provider name
  def provider
    llm_span = llm_spans.first
    return nil unless llm_span

    llm_span.dig("attributes", "llm.provider")
  end

  # Returns the model used (from LLM spans).
  #
  # @return [String, nil] Model name
  def model
    llm_span = llm_spans.first
    return nil unless llm_span

    llm_span.dig("attributes", "llm.model")
  end
end
