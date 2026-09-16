# frozen_string_literal: true

require "test_helper"

# Regression coverage for issue #109: the sandbox API used to look sessions up
# unscoped (any session_id reached any owner's sandbox) and to spawn provider
# jobs from #compare with no plan check and no usage increment at all.
#
# Sandboxes are the mounted engine's: every endpoint authenticates, so an
# anonymous caller is refused outright rather than scoped to a demo pool.
class Api::SandboxesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(email: "owner-#{SecureRandom.hex(4)}@example.com")
    @attacker = create_user(email: "attacker-#{SecureRandom.hex(4)}@example.com")

    @owner_sandbox = create_sandbox(user: @owner)
  end

  # ===========================================
  # Cross-owner access (set_sandbox scoping)
  # ===========================================

  test "show does not expose another owner's sandbox by session_id" do
    sign_in_as(@attacker)

    get "/dashboard/api/sandboxes/#{@owner_sandbox.session_id}"

    assert_response :not_found
  end

  test "show does not expose a signed-in owner's sandbox to an anonymous caller" do
    get "/dashboard/api/sandboxes/#{@owner_sandbox.session_id}", as: :json

    assert_response :unauthorized
  end

  test "show returns the caller's own sandbox" do
    sign_in_as(@owner)

    get "/dashboard/api/sandboxes/#{@owner_sandbox.session_id}"

    assert_response :success
    assert_equal @owner_sandbox.session_id, json_response["sandbox"]["session_id"]
  end

  test "run does not execute against another owner's sandbox" do
    sign_in_as(@attacker)

    assert_no_enqueued_jobs only: SandboxRunJob do
      post "/dashboard/api/sandboxes/#{@owner_sandbox.session_id}/run", params: { task: "Take a screenshot" }
    end

    assert_response :not_found
    assert_not @owner_sandbox.reload.running?
  end

  test "run does not execute against a signed-in owner's sandbox for an anonymous caller" do
    assert_no_enqueued_jobs only: SandboxRunJob do
      post "/dashboard/api/sandboxes/#{@owner_sandbox.session_id}/run", params: { task: "Take a screenshot" }, as: :json
    end

    assert_response :unauthorized
  end

  test "destroy does not expire another owner's sandbox" do
    sign_in_as(@attacker)

    delete "/dashboard/api/sandboxes/#{@owner_sandbox.session_id}"

    assert_response :not_found
    assert_not @owner_sandbox.reload.expired?
  end

  test "compare does not execute against another owner's sandbox" do
    sign_in_as(@attacker)

    assert_no_enqueued_jobs only: SandboxRunJob do
      post "/dashboard/api/sandboxes/compare", params: {
        task: "Take a screenshot",
        providers: %w[anthropic openai],
        sandbox_id: @owner_sandbox.session_id
      }
    end

    assert_response :not_found
    assert_not @owner_sandbox.reload.running?
  end

  # ===========================================
  # Ownership on create, metering on run
  # ===========================================

  test "create files a signed-in caller's sandbox under their user" do
    sign_in_as(@owner)

    post "/dashboard/api/sandboxes", params: { sandbox_type: "playwright_mcp" }

    assert_response :created
    created = SandboxSession.find_by!(session_id: json_response["sandbox"]["session_id"])
    assert_equal @owner.id, created.user_id
  end

  test "run records account usage for a signed-in caller" do
    account = create_account(owner: @owner)
    sign_in_as(@owner)

    assert_difference -> { account.reload.agent_runs_this_period }, 1 do
      post "/dashboard/api/sandboxes/#{@owner_sandbox.session_id}/run", params: { task: "Take a screenshot" }
    end

    assert_response :accepted
  end

  # ===========================================
  # compare metering
  # ===========================================

  test "compare records one execution per provider" do
    account = create_account(owner: @owner)
    sign_in_as(@owner)

    assert_difference -> { account.reload.agent_runs_this_period }, 2 do
      post "/dashboard/api/sandboxes/compare", params: {
        task: "Take a screenshot",
        providers: %w[anthropic openai],
        sandbox_id: @owner_sandbox.session_id
      }
    end

    assert_response :accepted
  end

  test "compare refuses to spawn provider jobs once the plan limit is reached" do
    account = create_account(owner: @owner)
    account.update!(agent_runs_this_period: account.effective_agent_runs_limit)
    sign_in_as(@owner)

    assert_no_enqueued_jobs only: SandboxRunJob do
      post "/dashboard/api/sandboxes/compare", params: {
        task: "Take a screenshot",
        providers: %w[anthropic openai],
        sandbox_id: @owner_sandbox.session_id
      }
    end

    assert_response :payment_required
    assert_equal "Plan limit reached", json_response["error"]
    assert json_response["upgrade_required"]
    assert_equal account.effective_agent_runs_limit, account.reload.agent_runs_this_period
    assert_not @owner_sandbox.reload.running?
  end

  test "compare at the plan limit does not create or provision a sandbox" do
    account = create_account(owner: @owner)
    account.update!(agent_runs_this_period: account.effective_agent_runs_limit)
    sign_in_as(@owner)

    assert_no_difference -> { SandboxSession.count } do
      post "/dashboard/api/sandboxes/compare", params: {
        task: "Take a screenshot",
        providers: %w[anthropic openai]
      }
    end

    assert_response :payment_required
  end

  test "compare still spawns a job per provider within the plan limit" do
    create_account(owner: @owner)
    sign_in_as(@owner)

    assert_enqueued_jobs 2, only: SandboxRunJob do
      post "/dashboard/api/sandboxes/compare", params: {
        task: "Take a screenshot",
        providers: %w[anthropic openai],
        sandbox_id: @owner_sandbox.session_id
      }
    end

    assert_response :accepted
    assert_equal 2, json_response["runs"].size
  end

  # ===========================================
  # compare provider params
  # ===========================================

  test "compare rejects a single provider sent as a bare string" do
    sign_in_as(@owner)

    assert_no_enqueued_jobs only: SandboxRunJob do
      post "/dashboard/api/sandboxes/compare", params: {
        task: "Take a screenshot",
        providers: "anthropic",
        sandbox_id: @owner_sandbox.session_id
      }
    end

    assert_response :bad_request
    assert_equal "providers must be a list of provider names", json_response["error"]
    assert_not @owner_sandbox.reload.running?
  end

  test "compare rejects a single provider sent as a bare string in a json body" do
    sign_in_as(@owner)

    assert_no_enqueued_jobs only: SandboxRunJob do
      post "/dashboard/api/sandboxes/compare",
        params: {
          task: "Take a screenshot",
          providers: "anthropic",
          sandbox_id: @owner_sandbox.session_id
        },
        as: :json
    end

    assert_response :bad_request
    assert_equal "providers must be a list of provider names", json_response["error"]
  end

  test "compare rejects a nested providers value without raising" do
    sign_in_as(@owner)

    assert_no_enqueued_jobs only: SandboxRunJob do
      post "/dashboard/api/sandboxes/compare", params: {
        task: "Take a screenshot",
        providers: { first: "anthropic", second: "openai" },
        sandbox_id: @owner_sandbox.session_id
      }
    end

    assert_response :bad_request
    assert json_response["error"].present?
    assert_not @owner_sandbox.reload.running?
  end

  test "compare still rejects an unknown provider name in an array" do
    sign_in_as(@owner)

    assert_no_enqueued_jobs only: SandboxRunJob do
      post "/dashboard/api/sandboxes/compare", params: {
        task: "Take a screenshot",
        providers: %w[anthropic bogus],
        sandbox_id: @owner_sandbox.session_id
      }
    end

    assert_response :bad_request
    assert_equal "Invalid providers: bogus", json_response["error"]
  end

  test "compare runs every provider of a valid array" do
    sign_in_as(@owner)

    assert_enqueued_jobs 2, only: SandboxRunJob do
      post "/dashboard/api/sandboxes/compare", params: {
        task: "Take a screenshot",
        providers: %w[anthropic openai],
        sandbox_id: @owner_sandbox.session_id
      }
    end

    assert_response :accepted
    assert_equal %w[anthropic openai], json_response["runs"].map { |run| run["provider"] }
  end

  private

  def create_sandbox(user:, **attrs)
    SandboxSession.create!(
      { sandbox_type: "playwright_mcp", status: :ready, user: user }.merge(attrs)
    )
  end
end
