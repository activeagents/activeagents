# frozen_string_literal: true

# Processes telemetry traces received from ActiveAgent clients.
#
# This job handles the asynchronous processing of trace data to avoid
# blocking the ingestion endpoint. It uses the same interface as
# ActiveAgent::ProcessTelemetryTracesJob from the gem for consistency.
#
# It:
# - Creates TelemetryTrace records for each trace
# - Updates aggregate statistics
# - Handles any errors gracefully
#
# @example
#   ProcessTelemetryTracesJob.perform_later(
#     account_id: 1,
#     traces: [...],
#     sdk_info: { name: "activeagent", version: "0.5.0" },
#     received_at: "2024-01-15T10:30:00Z"
#   )
#
class ProcessTelemetryTracesJob < ApplicationJob
  queue_as :default

  # Maximum traces to process in a single job to avoid memory issues
  MAX_TRACES_PER_JOB = 100

  def perform(account_id:, traces:, sdk_info:, received_at:)
    account = Account.find_by(id: account_id)
    return unless account

    traces = traces.take(MAX_TRACES_PER_JOB)

    traces.each do |trace|
      process_trace(trace, sdk_info, account)
    rescue StandardError => e
      Rails.logger.error(
        "[ProcessTelemetryTracesJob] Failed to process trace #{trace['trace_id']}: " \
        "#{e.class} - #{e.message}"
      )
    end
  end

  private

  def process_trace(trace, sdk_info, account)
    # Use the configured trace model from the gem
    model = ActiveAgent::Dashboard.trace_model

    # Skip if trace already exists (idempotency)
    return if model.exists?(trace_id: trace["trace_id"], account: account)

    # Use the gem's interface: create_from_payload(trace, sdk_info, account: account)
    model.create_from_payload(trace, sdk_info, account: account)
  end
end
