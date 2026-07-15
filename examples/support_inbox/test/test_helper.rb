ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Telemetry uses the test config: enabled + local_storage, so tests can
    # assert traces without a network.
  end
end
