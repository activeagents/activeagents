# frozen_string_literal: true

require "test_helper"

class Api::BenchmarksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @account = create_account(owner: @user)
    Rails.cache.delete(Api::BenchmarksController::CACHE_KEY)
  end

  teardown do
    Rails.cache.delete(Api::BenchmarksController::CACHE_KEY)
  end

  # --- authentication -------------------------------------------------------

  test "index rejects unauthenticated reads" do
    get "/api/benchmarks"

    assert_response :unauthorized
    assert_equal "Authentication required", json_response["error"]
  end

  # The abuse case from issue #107 is `{"requests":10,"io_ms":0,"cpu_iters":100000000}`,
  # which pins a CPU core inside the Puma worker. The 401 does not depend on the
  # payload, so this uses cheap knobs — a regression here must fail fast rather
  # than hang the suite executing the very benchmark it is asserting is blocked.
  test "run rejects unauthenticated benchmark triggers" do
    assert_no_enqueued_jobs(only: BenchmarkRunJob) do
      post "/api/benchmarks/run",
        params: { requests: 2, io_ms: 0, cpu_iters: 1, include_ractors: "false" }.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    assert_response :unauthorized
    assert_equal "Authentication required", json_response["error"]
    assert_nil Rails.cache.read(Api::BenchmarksController::CACHE_KEY)
  end

  test "create rejects unauthenticated ingest into the dashboard cache" do
    post "/api/benchmarks",
      params: { run_at: Time.now.iso8601, hardware: { cpu_model: "attacker" }, strategies: [] }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
    assert_nil Rails.cache.read(Api::BenchmarksController::CACHE_KEY)
  end

  test "index still serves authenticated readers" do
    sign_in_as(@user)

    get "/api/benchmarks"

    assert_response :success
    assert_equal [], json_response["runs"]
  end

  # --- parameter clamping ---------------------------------------------------

  test "run clamps oversized knobs before handing work to the background job" do
    sign_in_as(@user)

    assert_enqueued_with(job: BenchmarkRunJob) do
      post "/api/benchmarks/run",
        params: { requests: 10_000, io_ms: 60_000, cpu_iters: 100_000_000, include_ractors: "false" }.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    assert_response :success
    assert_equal "queued", json_response["status"]

    # Literals, not the controller constants: this must fail loudly if the caps
    # are removed, not quietly track whatever the controller happens to allow.
    options = enqueued_jobs.find { |j| j["job_class"] == "BenchmarkRunJob" }["arguments"].first
    assert_equal 25, options["requests"]
    assert_equal 1_000, options["io_ms"]
    assert_equal 100_000, options["cpu_iters"]
  end

  test "run clamps cpu_iters on the synchronous path" do
    sign_in_as(@user)

    post "/api/benchmarks/run",
      params: { requests: 2, io_ms: 0, cpu_iters: 500_000, include_ractors: "false" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :success
    config = json_response.dig("results", "config")
    assert_equal 100_000, config["cpu_iterations"]
    assert_equal 2, config["n_requests"]
  end

  test "run floors non-positive request counts instead of running zero requests" do
    sign_in_as(@user)

    post "/api/benchmarks/run",
      params: { requests: -50, io_ms: -1, cpu_iters: 1, include_ractors: "false" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :success
    config = json_response.dig("results", "config")
    assert_equal 1, config["n_requests"]
    assert_equal 0, config["io_latency_ms"]
  end
end
