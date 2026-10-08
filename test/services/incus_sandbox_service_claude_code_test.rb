# frozen_string_literal: true

require "test_helper"

# Claude Code on the Incus backend: the platform drives the image's
# sandbox-claude through the exec API and reads back what it writes. The fake
# answers each helper command from +helper+, serves the files the test puts
# in +files+, and records every exec and write.
class IncusSandboxServiceClaudeCodeTest < ActiveSupport::TestCase
  CONTAINER = "sandbox-1234abcd-0a0b0c0d"
  API_KEY = "sk-ant-api03-incusFixture"

  class FakeIncus < IncusSandboxService
    attr_reader :execs, :writes, :files

    def initialize(helper: {}, files: {}, directories: [])
      super({})
      @helper = helper
      @files = files
      @directories = directories
      @execs = []
      @writes = []
    end

    def helper_calls = execs.map { |exec| exec[:command] }

    private

    def exec_command(container_name, command, environment: {}, timeout: 120, user: nil)
      @execs << { container: container_name, command: command, environment: environment }
      answer = @helper.fetch(command[1] == "--spec" ? :restart : command[1]) { { exit: 0, stdout: "{}" } }
      answer = answer.call(environment) if answer.respond_to?(:call)
      { stdout: answer[:stdout].to_s, stderr: answer[:stderr].to_s, exit_code: answer[:exit] }
    end

    def read_container_file(_container_name, path, limit: MAX_FILE_BYTES, owner: nil)
      value = @files[path]
      value.respond_to?(:call) ? value.call : value
    end

    def read_container_range(container_name, path, offset, length, owner: nil)
      content = read_container_file(container_name, path) or return nil
      { data: content.b.byteslice(offset, length).to_s, size: content.bytesize }
    end

    def write_container_file(_container_name, path, content, type: "file", mode: "0600")
      @writes << { path: path, content: content, type: type, mode: mode }
    end

    def build_connection
      directories = @directories
      Struct.new(:directories) do
        def get(_path, params)
          Struct.new(:headers).new({ "X-Incus-Type" => directories.include?(params["path"]) ? "directory" : "file" })
        end
      end.new(directories)
    end

    def api_request(*) = { "operation" => nil }
    def wait_for_container_ready(*, **) = "10.0.0.5"
    def wait_for_mcp!(*) = true
    def sleep(_seconds) = nil
  end

  Sandbox = Struct.new(:session_id, :cloud_run_job_id, :runtime_environment, :checkout_spec, :project, :updates,
    keyword_init: true) do
    def update!(attributes)
      updates << attributes
      true
    end
  end

  def sandbox(environment: { "ANTHROPIC_API_KEY" => API_KEY }, project: nil)
    Sandbox.new(session_id: "1234abcd-session", cloud_run_job_id: CONTAINER, runtime_environment: environment,
      checkout_spec: nil, project: project, updates: [])
  end

  CodeSession = Struct.new(:id, :prompt, :model, :credential_mode, keyword_init: true)

  def session_directory(id) = "#{IncusSandboxService::ClaudeCode::SESSIONS_DIR}/#{id}"

  test "a session goes in by request and prompt files, runs detached, and streams its events back scrubbed" do
    directory = session_directory(41)
    statuses = [ { "status" => "running" }, { "status" => "finished", "exit_status" => 0 } ]
    events = +""
    service = FakeIncus.new(
      helper: { "session-start" => ->(_env) { events << %({"type":"system","subtype":"init"}\n{"type":"assistant","text":"key #{API_KEY}"}\n); { exit: 0, stdout: %({"status":"started"}) } } },
      files: {
        "#{directory}/status.json" => -> { JSON.generate(statuses.length > 1 ? statuses.shift : statuses.first) },
        "#{directory}/events.jsonl" => -> { events.tap { events << %({"type":"result","is_error":false}) if statuses.length == 1 && !events.include?("result") } },
        "#{directory}/diff.patch" => "diff --git a/app/agents/support_agent.rb b/app/agents/support_agent.rb\n+# #{API_KEY}\n",
        "#{directory}/stderr.log" => "warming up\n"
      }
    )
    received = []

    result = service.run_code_session(sandbox, CodeSession.new(id: 41, prompt: "Call the lookup tool.", model: "sonnet")) { |event| received << event }

    start = service.execs.find { |exec| exec[:command][1] == "session-start" }
    assert_equal [ "sandbox-claude", "session-start", "--dir", directory ], start[:command]
    assert_equal({ "ANTHROPIC_API_KEY" => API_KEY }, start[:environment], "the key reaches the container only as exec environment")
    request = JSON.parse(service.writes.find { |write| write[:path] == "#{directory}/request.json" }[:content])
    assert_equal "api_key", request["mode"]
    assert_includes request["argv"], "stream-json"
    assert_equal [ "--model", "sonnet" ], request["argv"].last(2)
    assert_includes request["pathspecs"], ":(exclude,glob,icase)**/.credentials.json"
    assert_equal "Call the lookup tool.", service.writes.find { |write| write[:path] == "#{directory}/prompt.txt" }[:content]
    service.writes.each { |write| assert_not_includes write[:content].to_s, API_KEY }

    assert_equal %w[system assistant result], received.map { |event| event["type"] }
    assert_equal "key [REDACTED]", received[1]["text"]
    assert_equal 0, result[:exit_status]
    assert_includes result[:diff], "+# [REDACTED]"
    assert_equal "warming up", result[:stderr_tail]
  end

  test "a session on a subscription login carries no credential, and an API-key session needs one" do
    directory = session_directory(42)
    service = FakeIncus.new(files: { "#{directory}/status.json" => %({"status":"finished","exit_status":0}) })

    service.run_code_session(sandbox, CodeSession.new(id: 42, prompt: "Fix it", credential_mode: "sandbox_login"))

    assert_equal({}, service.execs.first[:environment])
    assert_equal "sandbox_login", JSON.parse(service.writes.find { |write| write[:path].end_with?("request.json") }[:content])["mode"]
    error = assert_raises(IncusSandboxService::ContainerError) do
      FakeIncus.new.run_code_session(sandbox(environment: {}), CodeSession.new(id: 43, prompt: "Fix it"))
    end
    assert_match(/connect an Anthropic API key/, error.message)
  end

  test "a helper refusal fails the session with the helper's message" do
    service = FakeIncus.new(helper: { "session-start" => { exit: 2, stdout: %({"error":"session 40 is still running in this sandbox"}) } })

    error = assert_raises(IncusSandboxService::ContainerError) do
      service.run_code_session(sandbox, CodeSession.new(id: 44, prompt: "Fix it"))
    end
    assert_equal "session 40 is still running in this sandbox", error.message
  end

  test "cancel asks the helper to stop the session, and a sandbox without a container has nothing to stop" do
    service = FakeIncus.new
    assert service.cancel_code_session(sandbox, CodeSession.new(id: 45))
    assert_equal [ "sandbox-claude", "session-cancel", "--dir", session_directory(45) ], service.helper_calls.last

    gone = sandbox.tap { |record| record.cloud_run_job_id = nil }
    service = FakeIncus.new
    service.define_singleton_method(:handle_for) { |_| nil }
    assert service.cancel_code_session(gone, CodeSession.new(id: 46))
    assert_empty service.execs
  end

  test "sign-in: the code travels once as exec environment, and status reports only a flow state and a Claude login" do
    url = "https://claude.ai/oauth/authorize?code=true&client_id=fixture&state=synthetic"
    statuses = [
      %({"status":"awaiting_code","authorize_url":"#{url}","logged_in":false}),
      %({"status":"awaiting_code","authorize_url":"https://evil.example/oauth/authorize?client_id=x"}),
      %({"status":"connected","logged_in":true,"auth_method":"console"}),
      %({"status":"connected","logged_in":true,"auth_method":"claude.ai","email":"someone@example.com"}),
      %({"status":"pwned"})
    ]
    service = FakeIncus.new(helper: {
      "login-start" => { exit: 0, stdout: %({"status":"starting","logged_in":false,"auth_method":null}) },
      "login-code" => { exit: 0, stdout: %({"status":"submitted","logged_in":false,"auth_method":null}) },
      "login-status" => ->(_env) { { exit: 0, stdout: statuses.shift } },
      "logout" => { exit: 0, stdout: %({"status":"disconnected"}) }
    })

    assert_equal({ status: "starting", logged_in: false, auth_method: nil }, service.start_claude_login(sandbox))
    assert_equal [ "sandbox-claude", "login-start", "--timeout", "300" ], service.helper_calls.last

    assert_equal({ status: "awaiting_code", logged_in: false, auth_method: nil, authorize_url: url }, service.claude_login_status(sandbox))
    assert_nil service.claude_login_status(sandbox)[:authorize_url], "only Claude's own authorize URL is passed on"

    assert_equal "submitted", service.submit_claude_login_code(sandbox, "one-use-code")[:status]
    code_exec = service.execs.find { |exec| exec[:command][1] == "login-code" }
    assert_equal [ "sandbox-claude", "login-code" ], code_exec[:command]
    assert_equal({ "CLAUDE_LOGIN_CODE" => "one-use-code" }, code_exec[:environment])
    assert_raises(IncusSandboxService::ContainerError) { service.submit_claude_login_code(sandbox, "two words") }
    assert_equal 1, service.execs.count { |exec| exec[:command][1] == "login-code" }, "a malformed code never reaches the container"

    assert_equal({ status: "completed", logged_in: false, auth_method: nil }, service.claude_login_status(sandbox),
      "a Console login is not a subscription login")
    assert_equal({ status: "connected", logged_in: true, auth_method: "claude.ai" }, service.claude_login_status(sandbox))
    assert_equal "failed", service.claude_login_status(sandbox)[:status]

    assert service.claude_logout(sandbox)
    assert_equal [ "sandbox-claude", "logout" ], service.helper_calls.last
  end

  test "a refused code reports the helper's fixed message, never the code" do
    service = FakeIncus.new(helper: { "login-code" => { exit: 2, stdout: %({"error":"this sign-in is no longer waiting for a code; start again one-use-code"}) } })

    error = assert_raises(IncusSandboxService::ContainerError) { service.submit_claude_login_code(sandbox, "one-use-code") }
    assert_not_includes error.message, "one-use-code"
  end

  test "refresh restarts the app with the project's secrets and points the sandbox at the new runtime" do
    spec = { "secret_names" => [ "STRIPE_KEY" ], "timeout" => 600 }
    project = Struct.new(:secrets) do
      def boot_spec(_sandbox) = Struct.new(:to_h).new({ "secrets" => secrets })
    end
    service = FakeIncus.new(
      helper: { restart: { exit: 0, stdout: %({"status":"ready"}) } },
      files: { IncusSandboxService::BOOT_SPEC_PATH => JSON.generate(spec),
               IncusSandboxService::RUNTIME_MANIFEST => %({"mcp_path":"/activeagents/mcp","mcp_token":"aa_runtime_new"}) }
    )
    record = sandbox(project: project.new({ "STRIPE_KEY" => "sk_test_secret", "OTHER" => "unused" }))

    assert service.refresh_runtime(record)

    restart = service.execs.last
    assert_equal [ "sandbox-app-boot", "--spec", IncusSandboxService::BOOT_SPEC_PATH, "--restart" ], restart[:command]
    assert_equal({ "STRIPE_KEY" => "sk_test_secret" }, restart[:environment])
    assert_equal [ { runtime_mcp_url: "http://10.0.0.5:8080/activeagents/mcp", runtime_mcp_token: "aa_runtime_new" } ], record.updates

    missing = sandbox(project: project.new({}))
    error = assert_raises(IncusSandboxService::ContainerError) { service.refresh_runtime(missing) }
    assert_match(/needs its project secrets again: STRIPE_KEY/, error.message)
  end

  test "a restart that loses the app fails the sandbox, scrubbed" do
    project = Struct.new(:secrets) do
      def boot_spec(_sandbox) = Struct.new(:to_h).new({ "secrets" => secrets })
    end
    service = FakeIncus.new(
      helper: { restart: { exit: 1, stderr: "Sandbox start failed: server crashed with sk_test_secret" } },
      files: { IncusSandboxService::BOOT_SPEC_PATH => JSON.generate("secret_names" => [ "STRIPE_KEY" ]) }
    )
    record = sandbox(project: project.new({ "STRIPE_KEY" => "sk_test_secret" }))

    error = assert_raises(IncusSandboxService::ContainerError) { service.refresh_runtime(record) }

    assert_match(/server crashed with \[REDACTED\]/, error.message)
    assert_equal :failed, record.updates.last[:status]
    assert_not_includes record.updates.last[:error_message], "sk_test_secret"
  end

  test "terminating a sandbox revokes a Claude login in it first" do
    signed_in = FakeIncus.new(directories: [ IncusSandboxService::ClaudeCode::LOGIN_CONFIG ])
    signed_in.terminate(CONTAINER)
    assert_equal [ [ "sandbox-claude", "logout" ] ], signed_in.helper_calls

    signed_out = FakeIncus.new
    signed_out.terminate(CONTAINER)
    assert_empty signed_out.helper_calls
  end

  test "the orchestrator finds every Claude Code verb on this backend" do
    service = IncusSandboxService.new
    %i[run_code_session cancel_code_session refresh_runtime start_claude_login submit_claude_login_code claude_login_status claude_logout].each do |verb|
      assert service.respond_to?(verb), verb
    end
    assert_equal %w[claude_code], service.code_runners
  end
end
