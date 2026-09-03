# frozen_string_literal: true

require "test_helper"

class Api::BenchmarksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = create_user

    # The test environment's cache is :null_store, under which reads are nil
    # even after a write — every "nothing reached the cache" assertion would
    # pass vacuously. Swap in a real store so those assertions can fail.
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @original_cache
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

  test "create still ingests for an authenticated session and index serves the run back" do
    sign_in_as(@user)

    post "/api/benchmarks",
      params: { run_at: Time.now.iso8601, hardware: { cpu_model: "M1 Pro" }, strategies: [] }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :created
    assert json_response["ok"]

    get "/api/benchmarks"

    assert_response :success
    assert_equal "M1 Pro", json_response["runs"].first.dig("hardware", "cpu_model")
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

  # The clamps bound only Ragents::Providers::SimulatedProvider's work:
  # "realistic" ships its own multi-second latency model that ignores io_ms,
  # and "openai"/"anthropic" spend the deployment's real API keys.
  test "run rejects providers whose work the clamps cannot bound" do
    sign_in_as(@user)

    %w[realistic openai anthropic definitely-not-a-provider].each do |provider|
      assert_no_enqueued_jobs(only: BenchmarkRunJob) do
        post "/api/benchmarks/run",
          params: { requests: 2, io_ms: 0, cpu_iters: 1, provider: provider, include_ractors: "false" }.to_json,
          headers: { "Content-Type" => "application/json" }
      end

      assert_response :unprocessable_entity, "provider #{provider.inspect} was not rejected"
      assert_nil json_response["results"], "provider #{provider.inspect} executed a benchmark"
    end
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

  # A knob can arrive as a container rather than a scalar — `requests[]=1&requests[]=2`
  # from a query string, or a JSON object in the body. Array and
  # ActionController::Parameters do not respond to `to_i`, so reading them
  # directly raised NoMethodError and the action's rescue turned it into a 500.
  # The documented contract is the same for containers as for any other
  # non-numeric input: coerce to 0, then clamp up to the floor of the range.

  test "run coerces array-valued knobs instead of raising" do
    sign_in_as(@user)

    post "/api/benchmarks/run",
      params: { requests: [ 1, 2 ], io_ms: 0, cpu_iters: 1, include_ractors: "false" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :success, "array-valued knob was not coerced: #{response.body}"
    assert_nil json_response["error"]

    # Literals, not the controller constants: this must fail loudly if the
    # floors are removed, not quietly track whatever the controller allows.
    config = json_response.dig("results", "config")
    assert_equal 1, config["n_requests"]
  end

  test "run coerces nested-hash knob values instead of raising" do
    sign_in_as(@user)

    post "/api/benchmarks/run",
      params: { requests: { n: 2 }, io_ms: { ms: 5 }, cpu_iters: { iters: 9 }, include_ractors: "false" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :success, "nested-hash knob was not coerced: #{response.body}"
    assert_nil json_response["error"]

    config = json_response.dig("results", "config")
    assert_equal 1, config["n_requests"]
    assert_equal 0, config["io_latency_ms"]
    assert_equal 0, config["cpu_iterations"]
  end

  # --- error shape ----------------------------------------------------------

  # Backtrace frames carry absolute server paths, gem versions and internal
  # class structure. The exception is logged server-side; the client gets a
  # generic message and nothing else (#123).
  test "run does not return exception details or backtraces to the client" do
    sign_in_as(@user)

    # minitest 6 ships stubbing in a separate gem, so replace the constructor
    # by hand for the duration of the request.
    BenchmarkRunnerService.define_singleton_method(:new) { |**| raise "boom from /srv/app/lib/very_private.rb" }
    begin
      post "/api/benchmarks/run",
        params: { requests: 2, io_ms: 0, cpu_iters: 1, include_ractors: "false" }.to_json,
        headers: { "Content-Type" => "application/json" }
    ensure
      BenchmarkRunnerService.singleton_class.remove_method(:new)
    end

    assert_response :internal_server_error
    assert_equal "Benchmark run failed", json_response["error"]
    assert_nil json_response["backtrace"]
    assert_not_includes response.body, "very_private"
    assert_not_includes response.body, "boom"
  end

  # Positive control for the coercion above: ordinary scalars must still be
  # read as numbers and still be clamped, so a coercion that silently zeroed
  # every knob could not pass the two tests above unnoticed.
  test "run still reads ordinary scalar knobs and clamps them to the caps" do
    sign_in_as(@user)

    post "/api/benchmarks/run",
      params: { requests: 2, io_ms: 3, cpu_iters: 500_000, include_ractors: "false" }.to_json,
      headers: { "Content-Type" => "application/json" }

    assert_response :success
    config = json_response.dig("results", "config")
    assert_equal 2, config["n_requests"]
    assert_equal 3, config["io_latency_ms"]
    assert_equal 100_000, config["cpu_iterations"]
  end
end
