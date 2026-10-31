ENV["RAILS_ENV"] ||= "test"
# The suite never talks to a model provider or a search API: the framework's
# mock provider and the sample catalog stand in, and WebMock refuses the rest.
ENV["AI_PROVIDER"] = "mock"
ENV["PRODUCT_SEARCH_BACKEND"] = "catalog"

require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require_relative "test_helpers/session_test_helper"

WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def create_user(email: "ana@example.com", plan: "pay_as_you_go", admin: false, **attrs)
      User.create!(email_address: email, password: "password", plan_key: plan, admin: admin, **attrs)
    end

    # A hunt the sample catalog has good, over-budget and wrong-size matches for.
    def create_hunt(user, **attrs)
      user.hunts.create!({
        title: "Patagonia Synchilla Snap-T fleece, 90s",
        brand: "Patagonia",
        category: "clothing",
        keywords: "synchilla, snap-t, fleece, 90s",
        sizes: "M",
        max_price_cents: 15_000,
        condition: "vintage",
        frequency: "manual"
      }.merge(attrs))
    end
  end
end
