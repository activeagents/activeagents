# Queues a discovery run for every active, scheduled hunt whose next run
# time has passed. Solid Queue runs it on the schedule in
# config/recurring.yml; `bin/rails hunts:run_due` runs it by hand.
class ScheduleHuntsJob < ApplicationJob
  queue_as :default

  def perform
    queued = 0

    Hunt.due.includes(:user).find_each do |hunt|
      next if hunt.discovery_runs.in_progress.exists?

      hunt.run_now!(trigger: "scheduled")
      queued += 1
    end

    Rails.logger.info("[ScheduleHuntsJob] queued #{queued} scheduled hunt#{'s' unless queued == 1}")
    queued
  end
end
