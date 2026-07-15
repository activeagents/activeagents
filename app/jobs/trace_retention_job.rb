# frozen_string_literal: true

# Prunes telemetry traces past each account's plan retention window —
# backs the retention promises on the pricing page (Pro: 14 days,
# Enterprise: 400 days).
#
# NOT YET SCHEDULED: enabling recurring deletion of customer trace data
# (and choosing the free-tier window) is a product decision. To enable,
# add to config/recurring.yml:
#
#   trace_retention:
#     class: TraceRetentionJob
#     schedule: every day at 4am
class TraceRetentionJob < ApplicationJob
  queue_as :default

  # Retention window per plan slug
  RETENTION = {
    "free" => 14.days,
    "pro" => 14.days,
    "enterprise" => 400.days
  }.freeze

  BATCH_SIZE = 5_000

  def perform
    Account.find_each do |account|
      window = RETENTION.fetch(account.current_plan&.slug || "free", RETENTION["free"])
      cutoff = window.ago

      loop do
        deleted = account.telemetry_traces.where(timestamp: ...cutoff).limit(BATCH_SIZE).delete_all
        break if deleted < BATCH_SIZE
      end
    end
  end
end
