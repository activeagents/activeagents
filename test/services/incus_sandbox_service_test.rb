# frozen_string_literal: true

require "test_helper"

# The Incus backend booting an app_runtime sandbox from a GitHub checkout
# (activeagents/activeagent#479, #482): the repository is fetched and the app
# booted inside the container, and the runtime manifest becomes the session's
# MCP endpoint. The Incus API is replaced by a recording fake.
class IncusSandboxServiceTest < ActiveSupport::TestCase
  # Stands in for the Incus REST API: operations succeed immediately, the
  # container reports an address, and each exec answers from +exec_results+.
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
      in [ :post, %r{/exec\z} ]
        { "operation" => "/1.0/operations/exec-#{@requests.count { |r| r[1].end_with?('/exec') }}" }
      in [ :get, %r{/operations/exec-(\d+)\z} ]
        result = @exec_results.fetch($1.to_i - 1)
        { "metadata" => { "status" => "Success",
                          "metadata" => { "return" => result[:exit], "output" => { "1" => "/stdout-#{$1}", "2" => "/stderr-#{$1}" } } } }
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

  test "other sandbox types boot as before, with no checkout" do
    incus = FakeIncus.new([])
    session = session_double(checkout: nil)
    session.sandbox_type = "terminal"

    result = incus.create_sandbox(session)

    assert_nil result[:mcp_url]
    assert_empty incus.requests.select { |_, path, _| path.end_with?("/exec") }
  end
end
