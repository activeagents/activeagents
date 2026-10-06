# frozen_string_literal: true

require "test_helper"

# The Incus backend booting an app_runtime sandbox from a GitHub checkout
# (activeagents/activeagent#479, #482): the repository is fetched and the app
# booted inside the container, and the runtime manifest becomes the session's
# MCP endpoint. The Incus API is replaced by a recording fake.
class IncusSandboxServiceTest < ActiveSupport::TestCase
  # Stands in for the Incus REST API: operations succeed immediately, the
  # container reports an address, and each exec answers from +exec_results+
  # through log resources under the instance that ran it.
  class FakeIncus < IncusSandboxService
    attr_reader :requests

    def initialize(exec_results)
      super({})
      @exec_results = exec_results
      @requests = []
    end

    private

    def api_request(method, path, body = nil)
      @requests << [ method, path, body ]

      case [ method, path ]
      in [ :get, %r{/state\z} ]
        { "metadata" => { "status" => "Running",
                          "network" => { "eth0" => { "addresses" => [ { "family" => "inet", "scope" => "global", "address" => "10.0.0.5" } ] } } } }
      in [ :post, %r{\A/1\.0/instances/([^/]+)/exec\z} ]
        @container = $1
        { "operation" => "/1.0/operations/exec-#{@requests.count { |r| r[1].end_with?('/exec') }}" }
      in [ :get, %r{/operations/exec-(\d+)\z} ]
        number = $1
        result = @exec_results.fetch(number.to_i - 1)
        logs = "/1.0/instances/#{@container}/logs/exec-output"
        { "metadata" => { "status" => "Success",
                          "metadata" => { "return" => result[:exit], "output" => { "1" => "#{logs}/stdout-#{number}", "2" => "#{logs}/stderr-#{number}" } } } }
      in [ :get, %r{/stdout-(\d+)\z} ]
        @exec_results.fetch($1.to_i - 1)[:stdout].to_s
      in [ :get, %r{/stderr-(\d+)\z} ]
        @exec_results.fetch($1.to_i - 1)[:stderr].to_s
      in [ :get, %r{/operations/} ]
        { "metadata" => { "status" => "Success" } }
      else
        { "operation" => "/1.0/operations/#{SecureRandom.hex(2)}" }
      end
    end

    def service_ready?(_ip, **) = true
  end

  CHECKOUT = {
    repository: "acme/shop", ref: "main", clone_url: "https://github.com/acme/shop.git",
    username: "x-access-token", token: "gho_secret"
  }.freeze

  def session_double(checkout: CHECKOUT, environment: { "CLAUDE_CODE_OAUTH_TOKEN" => "sk-ant-oat01-x" })
    Struct.new(:session_id, :sandbox_type, :timeout_seconds, :checkout_spec, :runtime_environment, keyword_init: true)
      .new(session_id: SecureRandom.uuid, sandbox_type: "app_runtime", timeout_seconds: 900,
           checkout_spec: checkout, runtime_environment: environment)
  end

  test "an app_runtime sandbox fetches the checkout, boots it, and reports its MCP endpoint" do
    incus = FakeIncus.new([
      { exit: 0 },
      { exit: 0 },
      { exit: 0, stdout: { mcp_path: "/dashboard/mcp", mcp_token: "aa_runtime" }.to_json }
    ])

    result = incus.create_sandbox(session_double)

    assert_equal "http://10.0.0.5:8080/dashboard/mcp", result[:mcp_url]
    assert_equal "aa_runtime", result[:mcp_token]

    create = incus.requests.find { |method, path, _| method == :post && path == "/1.0/instances" }
    assert_equal "sandbox-app-runtime", create[2][:source][:alias]
    assert_not_includes create[2].to_json, "gho_secret", "the token must not be persisted in instance config"
    assert_not_includes create[2].to_json, "sk-ant-oat01", "nor the Claude Code credential"

    checkout, boot, manifest = incus.requests.select { |_, path, _| path.end_with?("/exec") }.map(&:last)
    assert_equal "gho_secret", checkout[:environment]["CHECKOUT_TOKEN"]
    assert_equal "main", checkout[:environment]["CHECKOUT_REF"]
    assert_not_includes checkout[:command].join(" "), "gho_secret", "the token travels in the environment, not argv"
    assert_equal [ IncusSandboxService::BOOT_COMMAND, IncusSandboxService::APP_DIR ], boot[:command]
    assert_equal({ "CLAUDE_CODE_OAUTH_TOKEN" => "sk-ant-oat01-x" }, boot[:environment])
    assert_equal [ "cat", IncusSandboxService::RUNTIME_MANIFEST ], manifest[:command]
  end

  test "a failed checkout fails the sandbox with git's error and cleans up" do
    incus = FakeIncus.new([ { exit: 128, stderr: "fatal: couldn't find remote ref nope" } ])

    error = assert_raises(IncusSandboxService::ContainerError) { incus.create_sandbox(session_double) }

    assert_match(/couldn't find remote ref/, error.message)
    assert incus.requests.any? { |method, path, _| method == :delete && path.start_with?("/1.0/instances/") }
  end

  test "a manifest without an MCP path is refused" do
    incus = FakeIncus.new([ { exit: 0 }, { exit: 0 }, { exit: 0, stdout: "{}" } ])

    error = assert_raises(IncusSandboxService::ContainerError) { incus.create_sandbox(session_double) }

    assert_match(/mcp_path/, error.message)
  end

  test "a sandbox's container is found by its session id" do
    incus = FakeIncus.new([])
    session = session_double
    def incus.list_sandboxes = [ { name: "sandbox-other-1", session_id: "someone-else" }, { name: "sandbox-mine-2", session_id: @mine } ]
    incus.instance_variable_set(:@mine, session.session_id)

    assert_equal "sandbox-mine-2", incus.handle_for(session)
    assert_nil incus.handle_for(session_double)
  end

  test "other sandbox types boot as before, with no checkout" do
    incus = FakeIncus.new([])
    session = session_double(checkout: nil)
    session.sandbox_type = "terminal"

    result = incus.create_sandbox(session)

    assert_nil result[:mcp_url]
    assert_empty incus.requests.select { |_, path, _| path.end_with?("/exec") }
  end
end

# The transport the service speaks to a daemon over: query parameters on GET,
# recorded exec output fetched from the instance that produced it, the HTTPS
# requirements, and the read-only preflight. Faraday's test adapter stands in
# for the daemon.
class IncusSandboxServiceTransportTest < ActiveSupport::TestCase
  setup do
    @stubs = Faraday::Adapter::Test::Stubs.new
    connection = Faraday.new do |f|
      f.request :json
      f.response :json
      f.response :raise_error
      f.adapter :test, @stubs
    end
    @service = IncusSandboxService.new(host: "https://incus.example.test:8443", project: "fixture-project")
    @service.define_singleton_method(:build_connection) { connection }
  end

  teardown do
    @stubs.verify_stubbed_calls
  end

  test "listing sends recursion and project and filters sandbox names" do
    @stubs.get("/1.0/instances?project=fixture-project&recursion=1") do
      json(metadata: [
        { name: "sandbox-fixture", status: "Running", config: { "user.session_id" => "fixture" } },
        { name: "sandboxing-unrelated" }, "/1.0/instances/not-expanded"
      ])
    end

    assert_equal [ { name: "sandbox-fixture", status: "Running", created_at: nil, session_id: "fixture" } ], @service.list_sandboxes
  end

  test "exec downloads recorded output and keeps exit status" do
    stub_exec(output: { "1" => "/1.0/instances/sandbox-fixture/logs/exec-output/fixture.stdout",
      "2" => "/1.0/instances/sandbox-fixture/logs/exec-output/fixture.stderr" }, exit_code: 7)
    @stubs.get("/1.0/instances/sandbox-fixture/logs/exec-output/fixture.stdout?project=fixture-project") { [ 200, { "Content-Type" => "application/octet-stream" }, "hello\n" ] }
    @stubs.get("/1.0/instances/sandbox-fixture/logs/exec-output/fixture.stderr?project=fixture-project") { [ 200, { "Content-Type" => "application/octet-stream" }, "failed\n" ] }

    assert_equal({ stdout: "hello\n", stderr: "failed\n", exit_code: 7 }, @service.exec_in_container("sandbox-fixture", [ "echo", "hello" ]))
  end

  test "exec never fetches an output URL on another host or instance" do
    [ "https://elsewhere.test/output", "/1.0/instances/another-instance/logs/out", "/1.0/instances/sandbox-fixture/logs/../secret" ].each do |url|
      assert_raises(IncusSandboxService::ContainerError) { @service.send(:recorded_output, "sandbox-fixture", url) }
    end
  end

  test "logs return content rather than a resource URL" do
    @service.define_singleton_method(:exec_in_container) do |_container, command|
      raise "wrong command" unless command == [ "cat", "/var/log/sandbox.log" ]

      { stdout: "sandbox ready\n", stderr: "", exit_code: 0 }
    end

    assert_equal "sandbox ready\n", @service.container_logs("sandbox-fixture")
  end

  test "preflight checks trust, project, profile and the checkout image without provisioning" do
    stub_preflight(image_status: 200)

    report = @service.preflight

    assert report[:connected]
    assert_equal "fixture-project", report[:project]
    assert_equal "fixture-version", report[:server_version]
    assert_equal 0, report[:sandbox_count]
    assert report[:app_runtime_supported], "the daemon carries the checkout image"
    assert_not report[:code_sessions_supported], "this backend has no run_code_session"
  end

  test "preflight reports a daemon without the checkout image" do
    stub_preflight(image_status: 404)

    assert_not @service.preflight[:app_runtime_supported]
  end

  test "preflight rejects an untrusted connection" do
    @stubs.get("/1.0?project=fixture-project") { json(metadata: { auth: "untrusted" }) }

    assert_raises(IncusSandboxService::ConnectionError) { @service.preflight }
  end

  test "transport configuration errors are actionable" do
    [
      [ { host: "unix:///missing/incus.socket" }, /Unix socket transport is not implemented/ ],
      [ { host: "http://incus.example.test" }, /HTTPS endpoint/ ],
      [ { host: "https://incus.example.test" }, /INCUS_CERT_PATH and INCUS_KEY_PATH/ ]
    ].each do |config, message|
      error = assert_raises(IncusSandboxService::ConnectionError) { IncusSandboxService.new(config).send(:build_connection) }
      assert_match message, error.message
    end
  end

  private

  def json(body, status = 200)
    [ status, { "Content-Type" => "application/json" }, JSON.generate(body) ]
  end

  def stub_exec(output:, exit_code:)
    @stubs.post("/1.0/instances/sandbox-fixture/exec?project=fixture-project") do |env|
      body = JSON.parse(env.body)
      assert_equal [ "echo", "hello" ], body["command"]
      assert_equal true, body["record-output"]
      assert_equal false, body["wait-for-websocket"]
      json(operation: "/1.0/operations/fixture-exec")
    end
    @stubs.get("/1.0/operations/fixture-exec?project=fixture-project") do
      json(metadata: { status: "Success", metadata: { return: exit_code, output: output } })
    end
  end

  def stub_preflight(image_status:)
    @stubs.get("/1.0?project=fixture-project") { json(metadata: { auth: "trusted", environment: { server_version: "fixture-version" } }) }
    @stubs.get("/1.0/projects/fixture-project?project=fixture-project") { json(metadata: {}) }
    @stubs.get("/1.0/profiles/sandbox-restricted?project=fixture-project") { json(metadata: {}) }
    @stubs.get("/1.0/instances?project=fixture-project&recursion=1") { json(metadata: []) }
    @stubs.get("/1.0/images/aliases/sandbox-app-runtime?project=fixture-project") do
      image_status == 200 ? json(metadata: { name: "sandbox-app-runtime" }) : json({ error: "not found" }, 404)
    end
  end
end
