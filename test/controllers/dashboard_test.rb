# frozen_string_literal: true

require "test_helper"

# The dashboard is the actionagent engine mounted at /dashboard, configured
# for this platform in config/initializers/action_agent.rb. These pin the
# seams that configuration sets: who gets in, where a signed-out browser is
# sent, and that the engine reads this app's unprefixed tables.
class DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    @agent = create_agent(user: @user, name: "Mounted Agent")
  end

  test "a signed-out browser is sent to this app's sign-in page" do
    get "/dashboard"

    assert_redirected_to "/session/new"
  end

  test "a signed-out API client gets a bare 401" do
    get "/dashboard/api/agents", as: :json

    assert_response :unauthorized
  end

  test "a signed-in user gets the engine's dashboard with their agents" do
    sign_in_as(@user)

    get "/dashboard"

    assert_response :success
    assert_includes response.body, "active-agent-dashboard"
    assert_includes response.body, "Mounted Agent"
  end

  test "the engine's API is scoped to the signed-in owner" do
    other = create_agent(user: create_user, name: "Someone Else's Agent")
    sign_in_as(@user)

    get "/dashboard/api/agents"

    assert_response :success
    names = json_response["agents"].map { |agent| agent["name"] }
    assert_includes names, "Mounted Agent"
    assert_not_includes names, other.name
  end

  test "the engine reads this app's unprefixed tables" do
    assert_equal "", ActionAgent.table_name_prefix
    assert_equal "agents", ActionAgent::Agent.table_name
    assert_equal "evaluation_scenarios", ActionAgent::EvaluationScenario.table_name
    assert_equal "active_agent_telemetry_traces", TelemetryTrace.table_name
    assert ActionAgent.multi_tenant?
  end
end
