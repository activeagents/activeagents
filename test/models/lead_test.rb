# frozen_string_literal: true

require "test_helper"

class LeadTest < ActiveSupport::TestCase
  def valid_attrs(**overrides)
    {
      name: "Jane Developer",
      email: "jane@example.com",
      service_type: "advisory"
    }.merge(overrides)
  end

  test "is valid with the required attributes" do
    assert Lead.new(valid_attrs).valid?
  end

  test "requires name, email, and service type" do
    lead = Lead.new
    assert_not lead.valid?
    assert lead.errors[:name].any?
    assert lead.errors[:email].any?
    assert lead.errors[:service_type].any?
  end

  test "rejects a malformed email" do
    assert_not Lead.new(valid_attrs(email: "not-an-email")).valid?
  end

  test "rejects a service type outside the allowed list" do
    assert_not Lead.new(valid_attrs(service_type: "hacking")).valid?
  end

  test "normalizes email casing and surrounding whitespace" do
    lead = Lead.create!(valid_attrs(email: "  Jane@Example.COM  "))
    assert_equal "jane@example.com", lead.email
  end

  test "normalizes name whitespace" do
    lead = Lead.create!(valid_attrs(name: "  Jane Developer  "))
    assert_equal "Jane Developer", lead.name
  end

  test "defaults to not synced with Resend" do
    assert_not Lead.create!(valid_attrs).synced_to_resend?
  end

  test "for_service scopes by service type" do
    advisory = Lead.create!(valid_attrs)
    Lead.create!(valid_attrs(email: "b@example.com", service_type: "workshop"))

    assert_equal [ advisory ], Lead.for_service("advisory").to_a
  end
end
