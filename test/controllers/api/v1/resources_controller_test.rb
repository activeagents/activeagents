# frozen_string_literal: true

require "test_helper"

class Api::V1::ResourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
  end

  def manifest_payload(service_name: "support_inbox")
    {
      service_name: service_name,
      environment: "production",
      resources: [
        {
          name: "Ticket",
          table_name: "tickets",
          columns: [
            { name: "subject", type: "string", null: false },
            { name: "status", type: "string", null: false, default: "open" }
          ],
          associations: [
            { kind: "has_many", name: "replies", class_name: "Reply" }
          ],
          record_count: 1042,
          admin_route: nil
        },
        {
          name: "Reply",
          table_name: "replies",
          columns: [ { name: "body", type: "text", null: false } ],
          associations: [ { kind: "belongs_to", name: "ticket", class_name: "Ticket" } ],
          record_count: 5210,
          admin_route: "/admin/replies"
        }
      ]
    }
  end

  test "rejects requests without an API key" do
    post "/v1/resources", params: manifest_payload, as: :json

    assert_response :unauthorized
    assert_equal "Missing Authorization header", json_response["error"]
  end

  test "rejects requests with an invalid API key" do
    post "/v1/resources", params: manifest_payload, as: :json,
      headers: { "Authorization" => "Bearer wrong" }

    assert_response :unauthorized
    assert_equal "Invalid API key", json_response["error"]
  end

  test "registers reported resources for the authenticated account" do
    post "/v1/resources", params: manifest_payload, as: :json,
      headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}" }

    assert_response :ok
    assert_equal 2, json_response["registered"]

    ticket = @account.admin_resources.find_by(name: "Ticket")
    assert_equal "support_inbox", ticket.service_name
    assert_equal "production", ticket.environment
    assert_equal "tickets", ticket.table_name
    assert_equal [ "subject", "status" ], ticket.column_names
    assert_equal 1042, ticket.record_count
    assert_not ticket.admin_ui?

    reply = @account.admin_resources.find_by(name: "Reply")
    assert_equal "/admin/replies", reply.admin_route
    assert reply.admin_ui?
  end

  test "accepts manifests authenticated with a generated API key" do
    api_key = @account.api_keys.create!(name: "reporter")

    post "/v1/resources", params: manifest_payload, as: :json,
      headers: { "Authorization" => "Bearer #{api_key.token}" }

    assert_response :ok
    assert_equal @account, AdminResource.find_by(name: "Ticket").account
    assert api_key.reload.last_used_at.present?, "expected ingest to record key usage"
  end

  test "re-reporting is an idempotent snapshot refresh" do
    2.times do
      post "/v1/resources", params: manifest_payload, as: :json,
        headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}" }
    end

    assert_equal 1, @account.admin_resources.where(name: "Ticket").count

    updated = manifest_payload
    updated[:resources][0][:columns] = [ { name: "subject", type: "string", null: false } ]
    updated[:resources][0][:record_count] = 1100

    post "/v1/resources", params: updated, as: :json,
      headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}" }

    ticket = @account.admin_resources.find_by(name: "Ticket")
    assert_equal [ "subject" ], ticket.column_names, "snapshot should replace columns, not merge"
    assert_equal 1100, ticket.record_count
  end

  test "skips entries without a name but registers the rest" do
    payload = manifest_payload
    payload[:resources] << { table_name: "orphans" }

    post "/v1/resources", params: payload, as: :json,
      headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}" }

    assert_response :ok
    assert_equal 2, json_response["registered"]
  end

  test "requires a service_name" do
    post "/v1/resources", params: { resources: [ { name: "Ticket" } ] }, as: :json,
      headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}" }

    assert_response :bad_request
  end

  test "caps resources per request" do
    payload = {
      service_name: "big_app",
      resources: (1..(Api::V1::ResourcesController::MAX_RESOURCES_PER_REQUEST + 5)).map { |i| { name: "Model#{i}" } }
    }

    post "/v1/resources", params: payload, as: :json,
      headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}" }

    assert_response :ok
    assert_equal Api::V1::ResourcesController::MAX_RESOURCES_PER_REQUEST, json_response["registered"]
  end

  test "skips entries that are not model class names or not objects" do
    payload = {
      service_name: "odd_app",
      resources: [
        { name: "Ticket" },
        { name: "not_a_class_name" },
        { name: "Ticket; DROP TABLE agents" },
        "just-a-string"
      ]
    }

    post "/v1/resources", params: payload, as: :json,
      headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}" }

    assert_response :ok
    assert_equal 1, json_response["registered"]
    assert_equal [ "Ticket" ], @account.admin_resources.pluck(:name)
  end

  test "alias route under /api/v1 also works" do
    post "/api/v1/resources", params: manifest_payload, as: :json,
      headers: { "Authorization" => "Bearer #{@account.telemetry_api_key}" }

    assert_response :ok
    assert_equal 2, json_response["registered"]
  end
end
