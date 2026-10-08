# frozen_string_literal: true

require "test_helper"
require "open3"
require "socket"

# docker/sandbox/app-runtime/sandbox-app-boot run against a scratch
# workspace: a spec with no user and no toolchain runs every command as the
# test's own user, and the "app" is a small Python HTTP server.
class SandboxAppBootTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("docker/sandbox/app-runtime/sandbox-app-boot").to_s
  SECRET = "sk_test_boot_secret_value"

  SERVER = <<~PYTHON
    import http.server, os
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            status = 405 if self.path == "/mcp" else int(os.environ.get("ROOT_STATUS", "200"))
            self.send_response(status)
            self.end_headers()
        def log_message(self, *args):
            pass
    http.server.HTTPServer(("127.0.0.1", int(os.environ["PORT"])), Handler).serve_forever()
  PYTHON

  setup do
    skip "python3 is not installed" unless system("python3", "--version", out: File::NULL, err: File::NULL)

    @root = Pathname(Dir.mktmpdir("sandbox-app-boot"))
    @app = @root.join("app")
    FileUtils.mkdir_p([ @app.join("bin"), @root.join("boot") ])
    @app.join("server.py").write(SERVER)
  end

  teardown do
    if @root
      [ state["server_pid"], state["forwarder_pid"] ].compact.each do |pid|
        Process.kill("-TERM", pid)
      rescue Errno::ESRCH
        nil
      end
      FileUtils.rm_rf(@root)
    end
  end

  def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end

  def spec(**overrides)
    {
      "version" => 1, "mode" => "spec", "kind" => "bootstrap", "app_dir" => @app.to_s,
      "manifest_path" => @root.join("runtime.json").to_s, "user" => nil, "port" => free_port, "listen_port" => nil,
      "timeout" => 60, "toolchain" => nil, "directories" => [ @root.join("db").to_s ], "env" => { "GREETING" => "hello" },
      "secret_names" => [ "APP_SECRET" ],
      "steps" => [ { "name" => "greet", "command" => "echo $GREETING $APP_SECRET", "timeout" => 10 } ],
      "manifest" => { "command" => %(printf '{"mcp_path":"/mcp","mcp_token":"aa_token"}' > "$ACTION_AGENT_SANDBOX_MANIFEST"), "timeout" => 10 },
      "start" => { "command" => "exec python3 server.py", "timeout" => 20 },
      "start_url" => "/", "keep_on_failure" => true,
      "recorded_steps" => [ { "name" => "checkout", "status" => "succeeded", "duration_ms" => 12 } ]
    }.merge(overrides.stringify_keys)
  end

  def boot(document, *arguments, env: { "APP_SECRET" => SECRET })
    path = @root.join("boot", "spec.json")
    path.write(JSON.generate(document))
    stdout, stderr, status = Open3.capture3(env, "python3", SCRIPT, "--spec", path.to_s, *arguments)
    [ status.exitstatus, stdout, stderr ]
  end

  def state
    path = @root.join("boot", "state.json")
    path.file? ? JSON.parse(path.read) : {}
  end

  def steps
    state["steps"].to_h { |step| [ step["name"], step["status"] ] }
  end

  def log(step)
    @root.join("boot", "logs", "#{step}.log").read
  end

  test "runs the steps, writes the manifest, and leaves the app answering" do
    document = spec(steps: [
      { "name" => "greet", "command" => %(echo $GREETING $APP_SECRET; printf %s "$APP_SECRET" | base64), "timeout" => 10 },
      { "name" => "add_engine", "command" => "exit 1", "timeout" => 10, "skip" => "the checkout already locks actionagent" }
    ])

    status, stdout, stderr = boot(document)

    assert_equal 0, status, stderr
    assert_equal "ready", JSON.parse(stdout)["status"]
    assert_equal({ "checkout" => "succeeded", "greet" => "succeeded", "add_engine" => "skipped", "manifest" => "succeeded",
                   "start" => "succeeded" }, steps)
    assert_equal %w[greet add_engine manifest start], state["resumable_steps"]
    assert_equal "ready", state["status"]
    assert_match(/hello \[REDACTED\]\n\[REDACTED\]/, log("greet"), "a secret is masked, its Base64 form too")
    assert_match(/# skipped: the checkout already locks actionagent/, log("add_engine"))
    assert_equal({ "mcp_path" => "/mcp", "mcp_token" => "aa_token" }, JSON.parse(@root.join("runtime.json").read))
    assert_equal "600", format("%o", @root.join("runtime.json").stat.mode & 0o777)
    assert @root.join("db").directory?
    assert_equal 405, Net::HTTP.get_response(URI("http://127.0.0.1:#{document["port"]}/mcp")).code.to_i
    assert_not_includes @root.join("boot").glob("**/*").select(&:file?).map(&:read).join, SECRET
  end

  test "--restart starts a ready boot's app again from its manifest, keeping the steps before it" do
    document = spec
    status, _stdout, stderr = boot(document)
    assert_equal 0, status, stderr
    first_server = state["server_pid"]
    @app.join("server.py").write(SERVER.sub("405 if", "401 if"))

    status, stdout, stderr = boot(document, "--restart")

    assert_equal 0, status, stderr
    assert_equal "ready", JSON.parse(stdout)["status"]
    assert state["restarted"]
    assert_nil state["resumed_from"]
    assert_equal({ "checkout" => "succeeded", "greet" => "succeeded", "manifest" => "succeeded", "start" => "succeeded" }, steps)
    assert_not_equal first_server, state["server_pid"]
    assert_equal 401, Net::HTTP.get_response(URI("http://127.0.0.1:#{document["port"]}/mcp")).code.to_i,
      "the changed code is what answers now"
    assert_equal 1, log("greet").scan("hello").length, "the step before the manifest did not run again"
  end

  test "--restart needs a ready boot" do
    document = spec(steps: [ { "name" => "broken", "command" => "exit 1", "timeout" => 10 } ])
    boot(document)

    status, _stdout, stderr = boot(document, "--restart")

    assert_equal 2, status
    assert_match(/no ready boot to restart/, stderr)
  end

  test "a step past its own timeout fails the boot, which is kept and names the step and the limit" do
    document = spec(steps: [
      { "name" => "greet", "command" => "echo hi", "timeout" => 10 },
      { "name" => "slow", "command" => "sleep 30", "timeout" => 1 }
    ])

    status, _stdout, stderr = boot(document)

    assert_equal 1, status
    assert_match(/\ASandbox slow failed: `sleep 30` did not finish within its 1s timeout/, stderr)
    assert_equal "failed", state["status"]
    assert_equal "slow", state["failed_step"]
    assert state["kept"]
    assert_equal({ "greet" => "succeeded", "slow" => "failed", "manifest" => "pending", "start" => "pending" }, steps.except("checkout"))
  end

  test "the boot's own limit bounds a step without a timeout of its own" do
    document = spec(timeout: 1, steps: [ { "name" => "slow", "command" => "sleep 30", "timeout" => nil } ])

    _status, _stdout, stderr = boot(document)

    assert_match(/did not finish within the boot timeout \(1s\)/, stderr)
  end

  test "a failed step's message carries the end of its log, masked" do
    document = spec(steps: [ { "name" => "migrate", "command" => "echo connecting with $APP_SECRET; exit 3", "timeout" => 10 } ])

    status, _stdout, stderr = boot(document)

    assert_equal 1, status
    assert_match(/exited with status 3\n--- last lines of logs\/migrate\.log ---\n/, stderr)
    assert_includes stderr, "connecting with [REDACTED]"
    assert_not_includes stderr, SECRET
  end

  test "a resume reruns the boot from the failed step and keeps what ran before it" do
    counter = @root.join("greeted")
    document = spec(steps: [
      { "name" => "greet", "command" => "echo once >> #{counter}", "timeout" => 10 },
      { "name" => "flaky", "command" => "test -f #{@root.join("fixed")}", "timeout" => 10 }
    ])
    assert_equal 1, boot(document).first

    FileUtils.touch(@root.join("fixed"))
    status, _stdout, stderr = boot(document, "--from", "flaky")

    assert_equal 0, status, stderr
    assert_equal "once\n", counter.read, "the step before the resumed one did not run again"
    assert_equal "flaky", state["resumed_from"]
    assert_equal({ "checkout" => "succeeded", "greet" => "succeeded", "flaky" => "succeeded", "manifest" => "succeeded", "start" => "succeeded" },
      steps, "the platform's recorded steps are kept too")
  end

  test "a manifest the app left as a symlink is not followed" do
    target = @root.join("elsewhere.json")
    target.write(%({"mcp_path":"/mcp"}))
    target.chmod(0o644)
    document = spec(manifest: { "command" => %(ln -s #{target} "$ACTION_AGENT_SANDBOX_MANIFEST"), "timeout" => 10 })

    status, _stdout, stderr = boot(document)

    assert_equal 1, status
    assert_match(/Sandbox manifest failed: the manifest is not a regular file/, stderr)
    assert_equal "644", format("%o", target.stat.mode & 0o777), "the file it points at keeps its mode"
  end

  test "run as root, the script refuses a spec anyone but root could have written or replaced" do
    check = <<~PYTHON
      import importlib.machinery, importlib.util, sys
      loader = importlib.machinery.SourceFileLoader("sandbox_app_boot", sys.argv[1])
      boot = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
      loader.exec_module(boot)
      for path in sys.argv[2:]:
          try:
              boot.require_root_only(path)
              print("accepted")
          except boot.Refused as error:
              print(f"refused: {error}")
    PYTHON
    spec_path = @root.join("boot", "spec.json")
    spec_path.write("{}")

    stdout, stderr, status = Open3.capture3("python3", "-B", "-c", check, SCRIPT, spec_path.to_s, "/usr/bin/env")

    assert status.success?, stderr
    mine, roots = stdout.lines(chomp: true)
    assert_match(/\Arefused: #{Regexp.escape(spec_path.to_s)} must be root's, writable by root alone and not a symlink/, mine)
    assert_equal "accepted", roots, "a file root owns, in directories only root can write"
  end

  test "a resume needs a failed boot and a step the boot has" do
    status, _stdout, stderr = boot(spec, "--from", "greet")
    assert_equal 2, status
    assert_match(/no failed boot to resume/, stderr)

    boot(spec(steps: [ { "name" => "broken", "command" => "exit 1", "timeout" => 10 } ]))
    status, _stdout, stderr = boot(spec(steps: [ { "name" => "broken", "command" => "exit 1", "timeout" => 10 } ]), "--from", "checkout")
    assert_equal 2, status
    assert_match(/"checkout" is not a step this boot can resume from/, stderr)
  end

  test "a step whose Rake task the app does not define is skipped" do
    rails = @app.join("bin", "rails")
    rails.write("#!/bin/sh\necho 'bin/rails css:build    # Build your CSS bundle'\n")
    rails.chmod(0o755)
    document = spec(steps: [
      { "name" => "css_build", "command" => "echo built css", "timeout" => 10, "if_task" => "css:build" },
      { "name" => "javascript_build", "command" => "exit 1", "timeout" => 10, "if_task" => "javascript:build" }
    ])

    status, _stdout, stderr = boot(document)

    assert_equal 0, status, stderr
    assert_equal "succeeded", steps["css_build"]
    assert_equal "skipped", steps["javascript_build"]
    assert_match(/the app defines no javascript:build task/, log("javascript_build"))
  end

  test "a start URL that answers 500 fails the start step" do
    status, _stdout, stderr = boot(spec(env: { "ROOT_STATUS" => "500" }))

    assert_equal 1, status
    assert_match(/Sandbox start failed: GET \/ answered 500/, stderr)
    assert_equal "start", state["failed_step"]
  end

  test "a server that exits before it answers fails the start step" do
    status, _stdout, stderr = boot(spec(start: { "command" => "exit 4", "timeout" => 10 }))

    assert_equal 1, status
    assert_match(/the server exited with status 4 before it answered/, stderr)
  end

  test "a spec of another version, or one missing a secret's value, is refused before anything runs" do
    status, _stdout, stderr = boot(spec(version: 2))
    assert_equal 2, status
    assert_match(/the boot spec is version 2; this image runs version 1/, stderr)

    status, _stdout, stderr = boot(spec, env: {})
    assert_equal 2, status
    assert_match(/needs APP_SECRET in its environment/, stderr)
    assert_empty state
  end

  test "the image's boot spec version is the one the service writes" do
    version = File.read(SCRIPT)[/^BOOT_SPEC_VERSION = (\d+)$/, 1]

    assert_equal IncusSandboxService::BOOT_SPEC_VERSION.to_s, version
  end
end
