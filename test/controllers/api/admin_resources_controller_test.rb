# frozen_string_literal: true

require "test_helper"

class Api::AdminResourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    @ticket = AdminResource.register_report!(
      account: @account,
      service_name: "support_inbox",
      environment: "production",
      payload: {
        "name" => "Ticket",
        "table_name" => "tickets",
        "columns" => [ { "name" => "subject", "type" => "string", "null" => false } ],
        "record_count" => 1042
      }
    )
    @reply = AdminResource.register_report!(
      account: @account,
      service_name: "support_inbox",
      payload: { "name" => "Reply", "table_name" => "replies", "admin_route" => "/admin/replies" }
    )
  end

  test "requires authentication" do
    get "/api/admin_resources"

    assert_redirected_to "/session/new"
  end

  test "lists the account's reported resources with service meta" do
    sign_in_as(@user)
    get "/api/admin_resources"

    assert_response :success
    assert_equal 2, json_response["resources"].size
    assert_equal [ "support_inbox" ], json_response["meta"]["services"]

    ticket = json_response["resources"].find { |r| r["name"] == "Ticket" }
    assert_equal "tickets", ticket["table_name"]
    assert_equal 1, ticket["column_count"]
    assert_equal 1042, ticket["record_count"]
    assert_equal false, ticket["admin_ui"]
    assert_nil ticket["agent"]
  end

  test "does not expose another account's resources" do
    other_user = create_user
    create_account(owner: other_user)

    sign_in_as(other_user)
    get "/api/admin_resources"

    assert_response :success
    assert_equal [], json_response["resources"]
  end

  test "show includes columns and associations" do
    sign_in_as(@user)
    get "/api/admin_resources/#{@ticket.id}"

    assert_response :success
    assert_equal "Ticket", json_response["resource"]["name"]
    assert_equal [ { "name" => "subject", "type" => "string", "null" => false } ], json_response["resource"]["columns"]
  end

  test "generate scaffolds an admin agent for one resource" do
    sign_in_as(@user)

    assert_difference -> { @user.agents.count }, 1 do
      post "/api/admin_resources/#{@ticket.id}/generate"
    end

    assert_response :success
    agent = json_response["resource"]["agent"]
    assert_equal "Ticket Admin", agent["name"]
    assert_equal "active", agent["status"]
    assert_equal agent["id"], json_response["agent_id"]
    assert_equal agent["id"], @ticket.reload.agent_id
  end

  test "generate is idempotent per resource" do
    sign_in_as(@user)
    post "/api/admin_resources/#{@ticket.id}/generate"

    assert_no_difference -> { @user.agents.count } do
      post "/api/admin_resources/#{@ticket.id}/generate"
    end

    assert_response :success
  end

  test "generate_all scaffolds agents for every resource of a service" do
    sign_in_as(@user)

    assert_difference -> { @user.agents.count }, 2 do
      post "/api/admin_resources/generate_all", params: { service_name: "support_inbox" }, as: :json
    end

    assert_response :success
    assert_equal 2, json_response["generated"]
    assert json_response["resources"].all? { |r| r["agent"].present? }
  end

  test "generate_all requires a service_name" do
    sign_in_as(@user)
    post "/api/admin_resources/generate_all", as: :json

    assert_response :bad_request
  end

  test "cannot generate for another account's resource" do
    other_user = create_user
    create_account(owner: other_user)

    sign_in_as(other_user)
    post "/api/admin_resources/#{@ticket.id}/generate"

    assert_response :not_found
  end

  test "regenerating a teammate's agent conflicts instead of overwriting" do
    teammate = create_user
    @account.account_memberships.create!(user: teammate, role: "member")

    sign_in_as(@user)
    post "/api/admin_resources/#{@ticket.id}/generate"
    owner_agent_id = json_response["agent_id"]

    sign_in_as(teammate)
    post "/api/admin_resources/#{@ticket.id}/generate"

    assert_response :conflict
    assert_equal owner_agent_id, @ticket.reload.agent_id

    get "/api/admin_resources"
    ticket = json_response["resources"].find { |r| r["name"] == "Ticket" }
    assert_equal false, ticket["agent"]["owned"]
  end

  test "generate_all skips a failing resource and still generates the rest" do
    calls = 0
    original = AdminAgentScaffold.method(:call)
    AdminAgentScaffold.define_singleton_method(:call) do |resource, user:|
      calls += 1
      raise ActiveRecord::RecordInvalid.new(Agent.new) if calls == 1

      original.call(resource, user: user)
    end

    sign_in_as(@user)
    post "/api/admin_resources/generate_all", params: { service_name: "support_inbox" }, as: :json

    assert_response :success
    assert_equal 1, json_response["generated"]
    assert_equal 1, json_response["skipped"].size
  ensure
    AdminAgentScaffold.define_singleton_method(:call, original) if original
  end
end
