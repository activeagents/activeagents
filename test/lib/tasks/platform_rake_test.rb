# frozen_string_literal: true

require "test_helper"
require "rake"

class PlatformRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("platform:bootstrap_account")
    Plan.find_or_create_by!(slug: "enterprise") { |plan| plan.name = "Enterprise" }
  end

  def bootstrap(env)
    previous = ENV.to_h.slice(*env.keys)
    env.each { |key, value| ENV[key] = value }
    output, = capture_io { Rake::Task["platform:bootstrap_account"].execute }
    output
  ensure
    env.each_key { |key| ENV[key] = previous[key] }
  end

  test "creates the login, its account and a key, and finds them again on a rerun" do
    first = bootstrap("EMAIL" => "local@example.com", "PASSWORD" => "password123", "PLAN" => "enterprise")
    second = bootstrap("EMAIL" => "local@example.com", "PLAN" => "enterprise")

    account = User.find_by(email_address: "local@example.com").owned_accounts.sole
    assert_equal first, second, "a rerun prints the same key"
    assert_equal "enterprise", account.current_plan.slug
    assert_equal 1, Pay::Subscription.count
  end

  test "refuses to comp an account that already pays through Stripe" do
    user = create_user(email: "paying@example.com")
    account = create_account(owner: user)
    customer = account.pay_customers.create!(processor: "stripe", processor_id: "cus_test", default: true)
    customer.subscriptions.create!(name: "default", processor_id: "sub_test", processor_plan: "price_test", status: "active")

    error = assert_raises(SystemExit) { bootstrap("EMAIL" => "paying@example.com", "PLAN" => "enterprise") }
    assert_equal 1, error.status
    assert_equal 1, Pay::Subscription.count, "no comp is added"
  end

  test "puts the key on an account the user owns, never one they only belong to" do
    member = create_user(email: "member@example.com")
    other = create_account(owner: create_user)
    other.account_memberships.create!(user: member, role: "member")

    bootstrap("EMAIL" => "member@example.com")

    assert_empty other.api_keys, "the other account gets no key"
    assert member.owned_accounts.sole.api_keys.exists?
  end
end
