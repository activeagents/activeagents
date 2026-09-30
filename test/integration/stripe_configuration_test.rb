require "test_helper"
require "open3"

class StripeConfigurationTest < ActiveSupport::TestCase
  test "deployed key wins over encrypted credentials and agrees with Pay after boot" do
    output, status = Open3.capture2e({
      "STRIPE_API_KEY" => "sk_test_syntheticbootcheck", "STRIPE_PRIVATE_KEY" => nil,
      "STRIPE_REQUIRE_TEST_MODE" => "true"
    }, RbConfig.ruby, "bin/rails", "runner",
      'abort "billing key mismatch" unless Stripe.api_key == ENV.fetch("STRIPE_API_KEY") && Stripe.api_key == Pay::Stripe.private_key')
    assert status.success?, output
  end

  test "staging test-mode guard rejects a live key during boot" do
    output, status = Open3.capture2e({
      "STRIPE_API_KEY" => "sk_live_syntheticbootcheck", "STRIPE_PRIVATE_KEY" => nil,
      "STRIPE_REQUIRE_TEST_MODE" => "true"
    }, RbConfig.ruby, "bin/rails", "runner", 'puts "booted"')
    assert_not status.success?
    assert_includes output, "Staging billing requires matching Stripe and Pay test keys"
  end
end
