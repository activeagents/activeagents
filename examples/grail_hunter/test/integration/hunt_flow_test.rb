require "test_helper"

class HuntFlowTest < ActionDispatch::IntegrationTest
  test "a collector signs up, creates a hunt, and the agent's findings land on the page" do
    post registration_path, params: { user: { name: "Ana", email_address: "ana@example.com", password: "password", password_confirmation: "password" } }
    assert_redirected_to hunts_path

    assert_enqueued_jobs 1, only: DiscoveryRunJob do
      post hunts_path, params: { hunt: {
        title: "Patagonia Synchilla Snap-T, 90s", brand: "Patagonia", category: "clothing",
        keywords: "synchilla, snap-t", sizes: "M", max_price: "150", currency: "USD",
        condition: "vintage", frequency: "manual"
      } }
    end
    hunt = Hunt.last
    assert_redirected_to hunt_path(hunt)
    assert_equal 15_000, hunt.max_price_cents
    assert_equal 199, hunt.discovery_runs.last.fee_cents

    get hunt_path(hunt)
    assert_response :success
    assert_match "Agent running", response.body

    perform_enqueued_jobs(only: DiscoveryRunJob)

    get hunt_path(hunt)
    assert_response :success
    assert_match "Completed", response.body
    finding = hunt.findings.by_score.first
    assert finding, "the run should have recorded findings"
    assert_match ERB::Util.html_escape(finding.title), response.body

    patch keep_finding_path(finding)
    assert finding.reload.saved?

    get findings_path(status: "saved")
    assert_match ERB::Util.html_escape(finding.title), response.body

    get hunt_run_path(hunt, hunt.discovery_runs.last)
    assert_response :success
    assert_match "Persisted conversation", response.body
  end

  test "a daily hunt needs a subscription" do
    sign_in_as create_user
    post hunts_path, params: { hunt: { title: "Seiko Pogue", frequency: "daily" } }

    assert_response :unprocessable_entity
    assert_match "included in the Pay as you go plan", response.body
  end

  test "hunts are private to their owner" do
    hunt = create_hunt(create_user(email: "owner@example.com"))
    sign_in_as create_user(email: "other@example.com")

    get hunt_path(hunt)
    assert_response :not_found
  end

  test "signed-out visitors see the pitch and the plans" do
    get root_path
    assert_response :success
    assert_match "Agents that hunt the rare stuff", response.body
    assert_match "Collector", response.body
  end
end
