# frozen_string_literal: true

# Transport contract tests deliberately require neither Rails nor a database.
require "minitest/autorun"
require "active_support/all"
require "faraday"
require_relative "../../app/services/incus_sandbox_service"

class IncusSandboxServiceTest < Minitest::Test
  def setup
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

  def teardown
    @stubs.verify_stubbed_calls
  end

  def test_listing_sends_recursion_and_project_and_filters_sandbox_names
    @stubs.get("/1.0/instances?project=fixture-project&recursion=1") do
      json(metadata: [
        { name: "sandbox-fixture", status: "Running", config: { "user.session_id" => "fixture" } },
        { name: "sandboxing-unrelated" }, "/1.0/instances/not-expanded"
      ])
    end
    assert_equal [ { name: "sandbox-fixture", status: "Running", created_at: nil, session_id: "fixture" } ], @service.list_sandboxes
  end

  def test_exec_downloads_recorded_output_and_keeps_exit_status
    stub_exec(output: { "1" => "/1.0/instances/sandbox-fixture/logs/exec-output/fixture.stdout",
      "2" => "/1.0/instances/sandbox-fixture/logs/exec-output/fixture.stderr" }, exit_code: 7)
    @stubs.get("/1.0/instances/sandbox-fixture/logs/exec-output/fixture.stdout?project=fixture-project") { [ 200, { "Content-Type" => "application/octet-stream" }, "hello\n" ] }
    @stubs.get("/1.0/instances/sandbox-fixture/logs/exec-output/fixture.stderr?project=fixture-project") { [ 200, { "Content-Type" => "application/octet-stream" }, "failed\n" ] }
    assert_equal({ stdout: "hello\n", stderr: "failed\n", exit_code: 7 }, @service.exec_in_container("sandbox-fixture", [ "echo", "hello" ]))
  end

  def test_exec_never_fetches_an_output_url_on_another_host_or_instance
    [ "https://elsewhere.test/output", "/1.0/instances/another-instance/logs/out", "/1.0/instances/sandbox-fixture/logs/../secret" ].each do |url|
      assert_raises(IncusSandboxService::ContainerError) { @service.send(:recorded_output, "sandbox-fixture", url) }
    end
  end

  def test_logs_return_content_rather_than_a_resource_url
    @service.define_singleton_method(:exec_in_container) do |_container, command|
      raise "wrong command" unless command == [ "cat", "/var/log/sandbox.log" ]

      { stdout: "sandbox ready\n", stderr: "", exit_code: 0 }
    end
    assert_equal "sandbox ready\n", @service.container_logs("sandbox-fixture")
  end

  def test_preflight_checks_trust_project_and_profile_without_provisioning
    @stubs.get("/1.0?project=fixture-project") { json(metadata: { auth: "trusted", environment: { server_version: "fixture-version" } }) }
    @stubs.get("/1.0/projects/fixture-project?project=fixture-project") { json(metadata: {}) }
    @stubs.get("/1.0/profiles/sandbox-restricted?project=fixture-project") { json(metadata: {}) }
    @stubs.get("/1.0/instances?project=fixture-project&recursion=1") { json(metadata: []) }
    report = @service.preflight
    assert report[:connected]
    assert_equal "fixture-project", report[:project]
    assert_equal 0, report[:sandbox_count]
    refute report[:app_runtime_supported]
    refute report[:code_sessions_supported]
  end

  def test_preflight_rejects_an_untrusted_connection
    @stubs.get("/1.0?project=fixture-project") { json(metadata: { auth: "untrusted" }) }
    assert_raises(IncusSandboxService::ConnectionError) { @service.preflight }
  end

  def test_checkout_creation_fails_before_allocating_a_base_container
    session = Struct.new(:sandbox_type).new("app_runtime")
    error = assert_raises(IncusSandboxService::ContainerError) { @service.create_sandbox(session) }
    assert_match(/checkout sandboxes are not implemented/, error.message)
  end

  def test_transport_configuration_errors_are_actionable
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

  def json(body)
    [ 200, { "Content-Type" => "application/json" }, JSON.generate(body) ]
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
end
