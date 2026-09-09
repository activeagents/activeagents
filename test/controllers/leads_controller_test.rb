# frozen_string_literal: true

require "test_helper"

class LeadsControllerTest < ActionDispatch::IntegrationTest
  def payload(**overrides)
    {
      name: "Jane Developer",
      email: "jane@example.com",
      company: "Acme Inc.",
      service_type: "advisory",
      message: "We want help shipping agents.",
      source: "landing_contact"
    }.merge(overrides)
  end

  test "creates a lead from the landing page form" do
    assert_difference -> { Lead.count }, 1 do
      post leads_path, params: payload, as: :json
    end

    assert_response :success
    assert json_response["success"]

    lead = Lead.order(:created_at).last
    assert_equal "jane@example.com", lead.email
    assert_equal "advisory", lead.service_type
    assert_equal "landing_contact", lead.source
    assert_not_nil lead.notified_at
  end

  test "notifies us and confirms to the lead" do
    assert_enqueued_emails 2 do
      post leads_path, params: payload, as: :json
    end
  end

  test "queues the Resend contact sync" do
    assert_enqueued_with(job: SyncLeadToResendJob) do
      post leads_path, params: payload, as: :json
    end
  end

  test "rejects an invalid email without creating a lead" do
    assert_no_difference -> { Lead.count } do
      post leads_path, params: payload(email: "nope"), as: :json
    end

    assert_response :unprocessable_entity
    assert json_response["error"].present?
  end

  test "rejects a missing name" do
    assert_no_difference -> { Lead.count } do
      post leads_path, params: payload(name: ""), as: :json
    end

    assert_response :unprocessable_entity
  end

  test "does not send email when validation fails" do
    assert_no_enqueued_emails do
      post leads_path, params: payload(email: "nope"), as: :json
    end
  end

  test "is reachable without authentication" do
    post leads_path, params: payload, as: :json
    assert_response :success
  end
end
