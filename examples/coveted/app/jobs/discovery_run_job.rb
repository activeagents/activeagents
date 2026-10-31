# Runs one discovery run through Discovery::Pipeline. The pipeline marks the
# run failed instead of raising, so a provider or search error is visible on
# the hunt page rather than retried blindly; the collector can run again.
class DiscoveryRunJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(run)
    run.perform!
  end
end
