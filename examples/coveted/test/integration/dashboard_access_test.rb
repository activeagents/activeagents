require "test_helper"

# The Active Agent dashboard shows every hunt's prompts and tool calls, so it
# is for admins only. config/initializers/action_agent.rb wires it to this
# app's session cookie.
class DashboardAccessTest < ActionDispatch::IntegrationTest
  test "signed-out visitors are sent to sign in" do
    get "/activeagents"
    assert_redirected_to "/session/new"
  end

  test "admins see the developer details on a check" do
    admin = create_user(email: "admin@example.com", admin: true)
    sign_in_as admin
    hunt = create_hunt(admin)
    run = hunt.discovery_runs.create!(user: admin, fee_cents: 0)
    Discovery::Pipeline.call(run)

    get hunt_run_path(hunt, run)
    assert_response :success
    assert_match "Details for admins", response.body
    assert_match "Persisted conversation", response.body
  end

  test "collectors are kept out, admins get in" do
    sign_in_as create_user(email: "collector@example.com")
    get "/activeagents"
    assert_redirected_to "/session/new"

    sign_in_as create_user(email: "admin@example.com", admin: true)
    get "/activeagents"
    assert_response :success
  end
end
