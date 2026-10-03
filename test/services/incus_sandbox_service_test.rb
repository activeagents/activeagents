# frozen_string_literal: true

require "test_helper"

# The Incus backend booting an app_runtime sandbox from a GitHub checkout: the
# repository is fetched into the container, the boot is resolved into a boot
# spec written there, and the image's boot command runs it. The Incus API is
# replaced by a recording fake: operations succeed immediately, the container
# reports an address, each exec answers from +exec_results+, and the instance
# file API reads and writes +files+.
class IncusSandboxServiceTest < ActiveSupport::TestCase
  class FakeIncus < IncusSandboxService
    attr_reader :requests, :writes, :probes

    def initialize(exec_results, files: {}, instances: [], mcp_statuses: [ 405 ])
      super({})
      @exec_results = exec_results
      @files = files
      @instances = instances
      @mcp_statuses = mcp_statuses
      @requests = []
      @writes = []
      @probes = []
    end

    def execs
      requests.select { |_, path, _| path.end_with?("/exec") }.map(&:last)
    end

    def deleted?
      requests.any? { |method, path, _| method == :delete && path.start_with?("/1.0/instances/") }
    end

    def written(path)
      JSON.parse(writes.reverse.find { |write| write[:path] == path }.fetch(:content))
    end

    private

    def api_request(method, path, body = nil)
      @requests << [ method, path, body ]

      case [ method, path ]
      in [ :get, "/1.0/instances" ]
        { "metadata" => @instances }
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

    def read_container_file(_container_name, path, limit: MAX_FILE_BYTES, owner: nil)
      @files[path]
    end

    def write_container_file(_container_name, path, content, type: "file", mode: "0600")
      @writes << { path: path, content: content, type: type, mode: mode }
      @files[path] = content if type == "file"
    end

    def mcp_status(ip, path)
      @probes << "#{ip}#{path}"
      @mcp_statuses.length > 1 ? @mcp_statuses.shift : @mcp_statuses.first
    end

    def service_ready?(_ip, **) = true

    def sleep(_seconds) = nil
  end

  CHECKOUT = {
    repository: "acme/shop", ref: "main", clone_url: "https://github.com/acme/shop.git",
    username: "x-access-token", token: "gho_secret_token_value"
  }.freeze
  MANIFEST = { "mcp_path" => "/dashboard/mcp", "mcp_token" => "aa_runtime" }.freeze
  APP = IncusSandboxService::APP_DIR

  setup do
    @switch = ENV[IncusSandboxService::APP_RUNTIME_SWITCH]
    ENV[IncusSandboxService::APP_RUNTIME_SWITCH] = "true"
  end

  teardown do
    ENV[IncusSandboxService::APP_RUNTIME_SWITCH] = @switch
  end

  def session_double(checkout: CHECKOUT, environment: { "CLAUDE_CODE_OAUTH_TOKEN" => "sk-ant-oat01-credential" },
    expires_at: 2.hours.from_now.change(usec: 0))
    Struct.new(:session_id, :sandbox_type, :timeout_seconds, :checkout_spec, :runtime_environment, :expires_at, keyword_init: true)
      .new(session_id: SecureRandom.uuid, sandbox_type: "app_runtime", timeout_seconds: 900,
           checkout_spec: checkout, runtime_environment: environment, expires_at: expires_at)
  end

  def lockfile(gems = {})
    specs = { "railties" => "8.0.2" }.merge(gems).map { |name, version| "    #{name} (#{version})\n" }.join
    "GEM\n  remote: https://rubygems.org/\n  specs:\n#{specs}\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n  railties\n\nBUNDLED WITH\n   2.6.2\n"
  end

  # A checkout as the file API reads it, and the manifest its boot writes.
  def checkout_files(**extra)
    {
      "#{APP}/Gemfile.lock" => lockfile, "#{APP}/config/application.rb" => "module Shop; end\n",
      "#{APP}/config/database.yml" => "development:\n  adapter: postgresql\n  database: shop_development\n",
      IncusSandboxService::RUNTIME_MANIFEST => MANIFEST.to_json
    }.merge(extra)
  end

  def bootstrap_spec(**overrides)
    {
      "kind" => "bootstrap", "apply" => "always", "preflight" => true,
      "steps" => [
        { "name" => "bundle_install", "command" => "bundle install", "timeout" => 900 },
        { "name" => "add_engine", "command" => %(bundle add actionagent --version "~> 1.9.0"), "timeout" => 900, "unless_locked" => "actionagent" },
        { "name" => "db_prepare", "command" => "bin/rails db:prepare", "timeout" => 900 }
      ],
      "env" => {}, "secrets" => { "STRIPE_TEST_KEY" => "sk_test_secret_value" },
      "manifest" => { "command" => "bin/rails action_agent:sandbox:manifest", "timeout" => 300 },
      "start" => { "command" => "bin/rails server -b 127.0.0.1 -p $PORT", "timeout" => 300 },
      "start_url" => "/", "keep_on_failure" => true, "timeout" => 1800
    }.merge(overrides.stringify_keys)
  end

  test "a checkout is fetched as the image's user, booted from the spec written into it, and reports its MCP endpoint" do
    incus = FakeIncus.new([ { exit: 0 }, { exit: 0, stdout: %({"status": "ready"}) } ], files: checkout_files)

    result = incus.create_sandbox(session_double)

    assert_equal "http://10.0.0.5:8080/dashboard/mcp", result[:mcp_url]
    assert_equal "aa_runtime", result[:mcp_token]
    assert_equal [ "10.0.0.5/dashboard/mcp" ], incus.probes, "readiness is the manifest's MCP path on the container's address"

    checkout, boot = incus.execs
    assert_equal IncusSandboxService::SANDBOX_UID, checkout[:user]
    assert_equal "gho_secret_token_value", checkout[:environment]["CHECKOUT_TOKEN"]
    assert_equal "main", checkout[:environment]["CHECKOUT_REF"]
    assert_not_includes checkout[:command].join(" "), "gho_secret_token_value", "the token travels in the environment, not argv"
    assert_includes IncusSandboxService::CHECKOUT_SCRIPT, "GIT_CONFIG_VALUE_1=\"$header\"", "git reads the header from its environment"
    assert_not_includes IncusSandboxService::CHECKOUT_SCRIPT, "git -c", "nor from its argv"

    assert_equal [ IncusSandboxService::BOOT_COMMAND, "--spec", IncusSandboxService::BOOT_SPEC_PATH ], boot[:command]
    assert_equal({}, boot[:environment], "the boot gets no Claude Code credential")
    assert_nil boot[:user], "the boot command runs as root and drops to the image's user itself"

    directory, spec = incus.writes
    assert_equal({ path: IncusSandboxService::BOOT_DIR, type: "directory", mode: "0700" }, directory.slice(:path, :type, :mode))
    assert_equal IncusSandboxService::BOOT_SPEC_PATH, spec[:path]
    document = JSON.parse(spec[:content])
    assert_equal "config", document["mode"]
    assert_equal %w[checkout], document["recorded_steps"].map { |step| step["name"] }
    assert_equal [ "postgresql" ], document.dig("toolchain", "services")
  end

  test "an engine boot spec's secrets reach the boot as its exec environment and nowhere else" do
    incus = FakeIncus.new([ { exit: 0 }, { exit: 0 } ], files: checkout_files)

    incus.create_sandbox(session_double, boot_config: bootstrap_spec)

    boot = incus.execs.last
    assert_equal({ "STRIPE_TEST_KEY" => "sk_test_secret_value" }, boot[:environment])
    document = incus.written(IncusSandboxService::BOOT_SPEC_PATH)
    assert_equal "spec", document["mode"]
    assert_equal [ "STRIPE_TEST_KEY" ], document["secret_names"]
    assert_equal({ "bundle_install" => 900, "add_engine" => 900, "db_prepare" => 900 }, document["steps"].to_h { |step| step.values_at("name", "timeout") })
    assert_equal 1800, document["timeout"]
    assert_equal %w[checkout preflight], document["recorded_steps"].map { |step| step["name"] }

    create = incus.requests.find { |method, path, _| method == :post && path == "/1.0/instances" }.last
    stored = incus.writes.map { |write| write[:content].to_s }.join + create.to_json
    assert_not_includes stored, "sk_test_secret_value", "no secret is written into the container or its config"
    assert_not_includes stored, "gho_secret_token_value"
  end

  test "an app_runtime container carries its session's expiry and none of the platform's variables" do
    session = session_double
    incus = FakeIncus.new([ { exit: 0 }, { exit: 0 } ], files: checkout_files)

    incus.create_sandbox(session)

    create = incus.requests.find { |method, path, _| method == :post && path == "/1.0/instances" }.last
    assert_equal "sandbox-app-runtime", create[:source][:alias]
    assert_equal session.expires_at.utc.iso8601, create[:config]["user.expires_at"]
    assert_empty create[:config].keys.grep(/\Aenvironment\./), "RAILS_ENV and the rest come from the boot spec"
    tier = SandboxInstanceTier.find(:cpu_small)
    assert_equal "#{tier.disk_gb}GB", create.dig(:devices, "root", "size")
    assert_equal tier.cpu_cores.to_s, create[:config]["limits.cpu"]
    assert_equal "#{tier.memory_gb}GB", create[:config]["limits.memory"]
    assert_not_includes create.to_json, "sk-ant-oat01", "nor the Claude Code credential"
  end

  test "a failed boot keeps its container when its spec asks to, and says why it failed" do
    failure = "Sandbox db_prepare failed: `bin/rails db:prepare` exited with status 1\n" \
      "--- last lines of logs/db_prepare.log ---\nPG::ConnectionBad using sk_test_secret_value"
    incus = FakeIncus.new([ { exit: 0 }, { exit: 1, stderr: failure } ], files: checkout_files)

    error = assert_raises(IncusSandboxService::ContainerError) { incus.create_sandbox(session_double, boot_config: bootstrap_spec) }

    assert_match(/Sandbox db_prepare failed/, error.message)
    assert_match(/kept for a resume/, error.message)
    assert_not_includes error.message, "sk_test_secret_value"
    assert_not incus.deleted?
  end

  test "a failed boot without keep_on_failure removes its container" do
    incus = FakeIncus.new([ { exit: 0 }, { exit: 1, stderr: "Sandbox setup failed: `bundle install` exited with status 5" } ], files: checkout_files)

    error = assert_raises(IncusSandboxService::ContainerError) { incus.create_sandbox(session_double) }

    assert_match(/Sandbox setup failed/, error.message)
    assert incus.deleted?
  end

  test "a checkout the preflight refuses is removed before any of its commands run" do
    files = checkout_files("#{APP}/Gemfile.lock" => lockfile("railties" => "7.1.3"))
    incus = FakeIncus.new([ { exit: 0 } ], files: files)

    error = assert_raises(IncusSandboxService::ContainerError) { incus.create_sandbox(session_double, boot_config: bootstrap_spec) }

    assert_match(/locks railties 7\.1\.3/, error.message)
    assert_equal 1, incus.execs.size, "only the fetch ran"
    assert_empty incus.writes
    assert incus.deleted?
  end

  test "a failed checkout fails the sandbox with git's error and cleans up" do
    incus = FakeIncus.new([ { exit: 128, stderr: "fatal: couldn't find remote ref nope" } ])

    error = assert_raises(IncusSandboxService::ContainerError) { incus.create_sandbox(session_double) }

    assert_match(/couldn't find remote ref/, error.message)
    assert incus.deleted?
  end

  test "a manifest without an MCP path is refused" do
    incus = FakeIncus.new([ { exit: 0 }, { exit: 0 } ], files: checkout_files(IncusSandboxService::RUNTIME_MANIFEST => "{}"))

    error = assert_raises(IncusSandboxService::ContainerError) { incus.create_sandbox(session_double) }

    assert_match(/mcp_path/, error.message)
  end

  test "readiness waits until the MCP path answers on the container's address" do
    incus = FakeIncus.new([ { exit: 0 }, { exit: 0 } ], files: checkout_files, mcp_statuses: [ nil, 404, 405 ])

    incus.create_sandbox(session_double)

    assert_equal 3, incus.probes.size
  end

  test "checkout sandboxes are refused while the platform's switch is off" do
    ENV[IncusSandboxService::APP_RUNTIME_SWITCH] = "false"
    incus = FakeIncus.new([])

    error = assert_raises(IncusSandboxService::ContainerError) { incus.create_sandbox(session_double) }

    assert_match(/switched off/, error.message)
    assert_empty incus.requests
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
    assert_empty incus.execs
    create = incus.requests.find { |method, path, _| method == :post && path == "/1.0/instances" }.last
    assert_equal "sandbox", create[:config]["environment.RAILS_ENV"]
    assert_nil create[:devices]
  end

  # --- Resuming -------------------------------------------------------------

  def kept_container(session, document:, state: { "status" => "failed", "kept" => true, "failed_step" => "db_prepare" })
    files = checkout_files(
      IncusSandboxService::BOOT_SPEC_PATH => document.to_json,
      IncusSandboxService::BOOT_STATE_PATH => state.to_json
    )
    instances = [ { "name" => "sandbox-kept-1", "config" => { "user.session_id" => session.session_id } } ]
    [ files, instances ]
  end

  def stored_document(boot_config)
    files = IncusSandboxService::BootSpec::FILES.index_with { |path| checkout_files["#{APP}/#{path}"] }
    IncusSandboxService::BootSpec.build(boot_config: boot_config, files: files,
      session_id: SecureRandom.uuid, repository: "acme/shop").document
  end

  test "a kept boot resumes from the step that failed, with its spec passed again" do
    session = session_double
    files, instances = kept_container(session, document: stored_document(bootstrap_spec))
    incus = FakeIncus.new([ { exit: 0 } ], files: files, instances: instances)

    result = incus.resume_boot(session, from: nil, boot_config: bootstrap_spec(secrets: { "STRIPE_TEST_KEY" => "sk_test_rotated_value" }))

    boot = incus.execs.sole
    assert_equal [ IncusSandboxService::BOOT_COMMAND, "--spec", IncusSandboxService::BOOT_SPEC_PATH, "--from", "db_prepare" ], boot[:command]
    assert_equal({ "STRIPE_TEST_KEY" => "sk_test_rotated_value" }, boot[:environment])
    assert_equal "sandbox-kept-1", result[:container_name]
    assert_equal "http://10.0.0.5:8080/dashboard/mcp", result[:mcp_url]
    assert_equal [ IncusSandboxService::BOOT_SPEC_PATH ], incus.writes.map { |write| write[:path] }, "the spec is rewritten; nothing is fetched again"
  end

  test "a kept boot whose spec had secrets cannot resume without it" do
    session = session_double
    files, instances = kept_container(session, document: stored_document(bootstrap_spec))
    incus = FakeIncus.new([], files: files, instances: instances)

    error = assert_raises(IncusSandboxService::ContainerError) { incus.resume_boot(session, from: "db_prepare") }

    assert_match(/needs its boot spec again: the values of STRIPE_TEST_KEY are never kept/, error.message)
    assert_empty incus.execs
  end

  test "a kept boot without secrets resumes from the step asked for, on the spec in its container" do
    session = session_double
    files, instances = kept_container(session, document: stored_document(bootstrap_spec(secrets: {})))
    incus = FakeIncus.new([ { exit: 0 } ], files: files, instances: instances)

    incus.resume_boot(session, from: "add_engine")

    assert_equal [ "--from", "add_engine" ], incus.execs.sole[:command].last(2)
    assert_empty incus.writes
  end

  test "a resumed boot that fails again is kept only while its spec asks to be" do
    session = session_double
    failure = { exit: 1, stderr: "Sandbox db_prepare failed: `bin/rails db:prepare` exited with status 1" }

    files, instances = kept_container(session, document: stored_document(bootstrap_spec(secrets: {})))
    kept = FakeIncus.new([ failure ], files: files, instances: instances)
    error = assert_raises(IncusSandboxService::ContainerError) { kept.resume_boot(session, from: nil) }
    assert_match(/Sandbox db_prepare failed.*kept for a resume/, error.message)
    assert_not kept.deleted?

    files, instances = kept_container(session, document: stored_document(bootstrap_spec(secrets: {})))
    removed = FakeIncus.new([ failure ], files: files, instances: instances)
    assert_raises(IncusSandboxService::ContainerError) do
      removed.resume_boot(session, from: nil, boot_config: bootstrap_spec(secrets: {}, keep_on_failure: false))
    end
    assert removed.deleted?
  end

  test "a resume is refused when nothing was kept, or from a step the boot does not have" do
    session = session_double
    files, instances = kept_container(session, document: stored_document(bootstrap_spec(secrets: {})), state: { "status" => "ready", "kept" => false })
    incus = FakeIncus.new([], files: files, instances: instances)
    error = assert_raises(IncusSandboxService::ContainerError) { incus.resume_boot(session, from: "db_prepare") }
    assert_match(/no failed boot kept to resume/, error.message)

    files, instances = kept_container(session, document: stored_document(bootstrap_spec(secrets: {})))
    incus = FakeIncus.new([], files: files, instances: instances)
    error = assert_raises(IncusSandboxService::ContainerError) { incus.resume_boot(session, from: "checkout") }
    assert_match(/"checkout" is not a step this boot can resume from/, error.message)

    assert_raises(IncusSandboxService::ContainerNotFoundError) { FakeIncus.new([]).resume_boot(session, from: nil) }
  end

  # --- Progress and logs ----------------------------------------------------

  test "boot status reports each step, scrubbed of the session's secrets" do
    session = session_double
    state = {
      "status" => "failed", "kept" => true, "failed_step" => "bundle_install", "mode" => "spec", "kind" => "bootstrap",
      "resumable_steps" => %w[toolchain bundle_install manifest start],
      "steps" => [
        { "name" => "checkout", "status" => "succeeded", "duration_ms" => 900 },
        { "name" => "bundle_install", "status" => "failed", "log" => "bundle_install", "detail" => "could not fetch with gho_secret_token_value" }
      ]
    }
    incus = FakeIncus.new([], files: { IncusSandboxService::BOOT_STATE_PATH => state.to_json },
      instances: [ { "name" => "sandbox-x", "config" => { "user.session_id" => session.session_id } } ])

    status = incus.boot_status(session)

    assert_equal({ mode: "spec", kind: "bootstrap", failed_step: "bundle_install", kept: true }, status.slice(:mode, :kind, :failed_step, :kept))
    assert_equal %w[toolchain bundle_install manifest start], status[:resumable_steps]
    assert_equal "could not fetch with [REDACTED]", status[:steps].last[:detail]
    assert_nil FakeIncus.new([]).boot_status(session)
  end

  test "a boot log is read in pages that end at a line break, scrubbed" do
    session = session_double
    state = { "steps" => [ { "name" => "bundle_install", "log" => "bundle_install" } ] }
    log = "Fetching gem metadata\nusing gho_secret_token_value\nInstalling pg 1.5.9\n"
    incus = FakeIncus.new([], files: { IncusSandboxService::BOOT_STATE_PATH => state.to_json, "#{IncusSandboxService::BOOT_DIR}/logs/bundle_install.log" => log },
      instances: [ { "name" => "sandbox-x", "config" => { "user.session_id" => session.session_id } } ])

    page = incus.boot_log(session, step: "bundle_install", offset: 0, limit: 30)

    assert_equal "Fetching gem metadata\n", page[:text]
    assert_equal 22, page[:next_offset]
    assert_not page[:eof]
    rest = incus.boot_log(session, step: "bundle_install", offset: page[:next_offset], limit: 1024)
    assert_equal "using [REDACTED]\nInstalling pg 1.5.9\n", rest[:text]
    assert rest[:eof]
    assert_nil incus.boot_log(session, step: "checkout")
  end

  # --- Lifetime and capabilities --------------------------------------------

  test "expired containers are removed by their session's expiry, and unlabelled ones by age" do
    incus = FakeIncus.new([])
    now = Time.current
    def incus.list_sandboxes = @sandboxes
    incus.instance_variable_set(:@sandboxes, [
      { name: "sandbox-checkout", created_at: (now - 1.hour).iso8601, expires_at: (now + 1.hour).utc.iso8601 },
      { name: "sandbox-expired", created_at: (now - 3.hours).iso8601, expires_at: (now - 1.hour).utc.iso8601 },
      { name: "sandbox-legacy", created_at: (now - 1.hour).iso8601, expires_at: nil }
    ])

    assert_equal 2, incus.cleanup_expired
    deleted = incus.requests.select { |method, _| method == :delete }.map { |_, path| path.split("/").last }
    assert_equal %w[sandbox-expired sandbox-legacy], deleted
  end

  test "features say checkouts cannot boot while the switch is off, without asking the daemon" do
    ENV[IncusSandboxService::APP_RUNTIME_SWITCH] = "false"
    incus = FakeIncus.new([])

    assert_equal false, incus.features[:app_runtime]
    assert_equal IncusSandboxService::BOOT_SPEC_VERSION, incus.features[:boot_spec_version]
    assert_empty incus.requests
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

    assert_equal [ { name: "sandbox-fixture", status: "Running", created_at: nil, expires_at: nil, session_id: "fixture" } ], @service.list_sandboxes
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
    stub_preflight(image_version: "1")

    report = with_switch("true") { @service.preflight }

    assert report[:connected]
    assert_equal "fixture-project", report[:project]
    assert_equal "fixture-version", report[:server_version]
    assert_equal 0, report[:sandbox_count]
    assert report[:app_runtime_enabled]
    assert_equal({ present: true, boot_spec_version: "1", expected_boot_spec_version: 1 }, report[:app_runtime_image])
    assert report[:app_runtime_supported], "the daemon carries the checkout image at this service's boot spec version"
    assert_not report[:code_sessions_supported], "this backend has no run_code_session"
  end

  test "preflight reports a daemon without the checkout image" do
    stub_preflight(image_version: nil)

    report = with_switch("true") { @service.preflight }

    assert_equal false, report[:app_runtime_image][:present]
    assert_not report[:app_runtime_supported]
  end

  test "preflight reports an image of another boot spec version as unsupported" do
    stub_preflight(image_version: "2")

    report = with_switch("true") { @service.preflight }

    assert_equal "2", report[:app_runtime_image][:boot_spec_version]
    assert_not report[:app_runtime_supported]
  end

  test "preflight reports checkouts unsupported while the switch is off, whatever the image" do
    stub_preflight(image_version: "1")

    report = with_switch(nil) { @service.preflight }

    assert_not report[:app_runtime_enabled]
    assert_not report[:app_runtime_supported]
  end

  test "features report checkouts as available when the switch is on and the image matches" do
    @stubs.get("/1.0/images/aliases/sandbox-app-runtime?project=fixture-project") { json(metadata: { target: "abc123" }) }
    @stubs.get("/1.0/images/abc123?project=fixture-project") { json(metadata: { properties: { boot_spec_version: "1" } }) }

    assert with_switch("true") { @service.features[:app_runtime] }
  end

  test "a container file is read through the file API, and only when it is a regular file" do
    path = "/1.0/instances/sandbox-fixture/files"
    @stubs.get("#{path}?path=%2Fworkspace%2Fapp%2FGemfile.lock&project=fixture-project") do
      [ 200, { "Content-Type" => "application/octet-stream", "X-Incus-Type" => "file" }, "GEM\n" ]
    end
    @stubs.get("#{path}?path=%2Fworkspace%2Fapp%2Fconfig%2Fdatabase.yml&project=fixture-project") do
      [ 200, { "Content-Type" => "application/octet-stream", "X-Incus-Type" => "symlink" }, "/etc/shadow" ]
    end
    @stubs.get("#{path}?path=%2Fworkspace%2Fapp%2F.nvmrc&project=fixture-project") { json({ error: "not found" }, 404) }
    @stubs.get("#{path}?path=%2Fworkspace%2Fboot%2Flogs%2Fbig.log&project=fixture-project") do
      [ 200, { "Content-Type" => "application/octet-stream", "X-Incus-Type" => "file" }, "x" * 11 ]
    end

    assert_equal "GEM\n", @service.send(:read_container_file, "sandbox-fixture", "/workspace/app/Gemfile.lock")
    assert_nil @service.send(:read_container_file, "sandbox-fixture", "/workspace/app/config/database.yml"), "a symlink is never followed"
    assert_nil @service.send(:read_container_file, "sandbox-fixture", "/workspace/app/.nvmrc")
    assert_raises(IncusSandboxService::ContainerError) do
      @service.send(:read_container_file, "sandbox-fixture", "/workspace/boot/logs/big.log", limit: 10)
    end
  end

  test "a file read for its owner is nil when another uid owns it" do
    path = "/1.0/instances/sandbox-fixture/files?path=%2Fworkspace%2Fboot%2Fstate.json&project=fixture-project"
    @stubs.get(path) { [ 200, { "Content-Type" => "application/octet-stream", "X-Incus-Type" => "file", "X-Incus-Uid" => "1000" }, "{}" ] }
    @stubs.get(path) { [ 200, { "Content-Type" => "application/octet-stream", "X-Incus-Type" => "file", "X-Incus-Uid" => "0" }, "{}" ] }

    assert_nil @service.send(:read_container_file, "sandbox-fixture", "/workspace/boot/state.json", owner: 0)
    assert_equal "{}", @service.send(:read_container_file, "sandbox-fixture", "/workspace/boot/state.json", owner: 0)
  end

  test "a file is written into the container owned by root and private" do
    @stubs.post("/1.0/instances/sandbox-fixture/files?path=%2Fworkspace%2Fboot%2Fspec.json&project=fixture-project") do |env|
      assert_equal "{}", env.body
      assert_equal({ "X-Incus-Type" => "file", "X-Incus-Uid" => "0", "X-Incus-Gid" => "0", "X-Incus-Mode" => "0600" },
        env.request_headers.to_h.slice("X-Incus-Type", "X-Incus-Uid", "X-Incus-Gid", "X-Incus-Mode"))
      json(metadata: {})
    end

    @service.send(:write_container_file, "sandbox-fixture", "/workspace/boot/spec.json", "{}")
  end

  test "a command can run as the image's user" do
    @stubs.post("/1.0/instances/sandbox-fixture/exec?project=fixture-project") do |env|
      body = JSON.parse(env.body)
      assert_equal [ 1000, 1000 ], body.values_at("user", "group")
      assert_equal({ "HOME" => "/home/sandbox" }, body["environment"])
      json(operation: "/1.0/operations/fixture-exec")
    end
    @stubs.get("/1.0/operations/fixture-exec?project=fixture-project") { json(metadata: { status: "Success", metadata: { return: 0, output: {} } }) }

    result = @service.send(:exec_command, "sandbox-fixture", [ "true" ], environment: { "HOME" => "/home/sandbox" }, user: 1000)

    assert_equal 0, result[:exit_code]
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

  def stub_preflight(image_version:)
    @stubs.get("/1.0?project=fixture-project") { json(metadata: { auth: "trusted", environment: { server_version: "fixture-version" } }) }
    @stubs.get("/1.0/projects/fixture-project?project=fixture-project") { json(metadata: {}) }
    @stubs.get("/1.0/profiles/sandbox-restricted?project=fixture-project") { json(metadata: {}) }
    @stubs.get("/1.0/instances?project=fixture-project&recursion=1") { json(metadata: []) }
    @stubs.get("/1.0/images/aliases/sandbox-app-runtime?project=fixture-project") do
      image_version ? json(metadata: { name: "sandbox-app-runtime", target: "fixture-fingerprint" }) : json({ error: "not found" }, 404)
    end
    return unless image_version

    @stubs.get("/1.0/images/fixture-fingerprint?project=fixture-project") do
      json(metadata: { fingerprint: "fixture-fingerprint", properties: { boot_spec_version: image_version } })
    end
  end

  def with_switch(value)
    previous = ENV[IncusSandboxService::APP_RUNTIME_SWITCH]
    ENV[IncusSandboxService::APP_RUNTIME_SWITCH] = value
    yield
  ensure
    ENV[IncusSandboxService::APP_RUNTIME_SWITCH] = previous
  end
end
