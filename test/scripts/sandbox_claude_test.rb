# frozen_string_literal: true

require "test_helper"
require "open3"
require "etc"

# docker/sandbox/app-runtime/sandbox-claude run against a scratch workspace
# with a fake `claude`: the test's own user stands in for both the image's
# `claude` and `sandbox` users, so nothing here needs root.
class SandboxClaudeTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("docker/sandbox/app-runtime/sandbox-claude").to_s

  FAKE_CLAUDE = <<~PYTHON
    #!/usr/bin/env python3
    import json, os, sys
    here = os.path.dirname(os.path.abspath(__file__))
    config = os.environ.get("CLAUDE_CONFIG_DIR", "")
    def note(line):
        with open(os.path.join(here, "calls.log"), "a") as log:
            log.write(line + "\\n")
    args = sys.argv[1:]
    if args[:2] == ["auth", "login"]:
        print("Browser didn't open? Use the url below to sign in:")
        print("https://claude.ai/oauth/authorize?code=true&client_id=fixture&state=synthetic")
        print("Paste code here if prompted >", flush=True)
        code = sys.stdin.readline().strip()
        if code != "one-use-code":
            sys.exit(1)
        with open(os.path.join(config, ".credentials.json"), "w") as file:
            file.write('{"claudeAiOauth":{"accessToken":"sk-ant-oat01-fixture"}}')
        print("Login successful.")
    elif args[:3] == ["auth", "status", "--json"]:
        signed_in = os.path.exists(os.path.join(config, ".credentials.json"))
        print(json.dumps({"loggedIn": signed_in, "authMethod": "claude.ai"} if signed_in else {"loggedIn": False}))
    elif args[:2] == ["auth", "logout"]:
        note("logout " + config)
        try:
            os.remove(os.path.join(config, ".credentials.json"))
        except FileNotFoundError:
            pass
    elif "-p" in args:
        prompt = sys.stdin.read()
        note("session key=" + ("present" if os.environ.get("ANTHROPIC_API_KEY") else "absent") + " config=" + config)
        print(json.dumps({"type": "system", "subtype": "init"}), flush=True)
        with open("agent.rb", "a") as file:
            file.write("# fixed: " + prompt.strip() + "\\n")
        if os.environ.get("FAKE_HANG") or "hang" in prompt:
            import time
            time.sleep(60)
        print(json.dumps({"type": "result", "is_error": False, "result": "Fixed it."}), flush=True)
    else:
        sys.exit(2)
  PYTHON

  setup do
    skip "python3 is not installed" unless system("python3", "--version", out: File::NULL, err: File::NULL)
    skip "git is not installed" unless system("git", "--version", out: File::NULL, err: File::NULL)

    @root = Pathname(Dir.mktmpdir("sandbox-claude"))
    @app = @root.join("app")
    @app.mkpath
    @bin = @root.join("bin")
    @bin.mkpath
    @claude = @bin.join("claude")
    @claude.write(FAKE_CLAUDE)
    @claude.chmod(0o755)
    @app.join("agent.rb").write("class SupportAgent; end\n")
    git = { "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@example.com",
            "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => "t@example.com" }
    system(git, "git", "-C", @app.to_s, "init", "-q") &&
      system(git, "git", "-C", @app.to_s, "add", ".") &&
      system(git, "git", "-C", @app.to_s, "commit", "-qm", "base") or flunk "could not make the fixture repository"
    @user = Etc.getpwuid(Process.uid).name
    @home = @root.join("home")
    @home.mkpath
    @home.chmod(0o700)
  end

  teardown do
    next unless @root

    begin
      pid = read_json(@root.join("claude", "login", "supervisor.json"))["pid"]
      Process.kill("-KILL", pid) if pid
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end
    FileUtils.rm_rf(@root)
  end

  def env(extra = {})
    {
      "SANDBOX_APP_DIR" => @app.to_s, "SANDBOX_CLAUDE_ROOT" => @root.join("claude").to_s,
      "SANDBOX_BOOT_SPEC" => @root.join("no-spec.json").to_s, "SANDBOX_CLAUDE_USER" => @user,
      "SANDBOX_APP_USER" => @user, "SANDBOX_CLAUDE_BIN" => @claude.to_s, "SANDBOX_CLAUDE_HOME" => @home.to_s
    }.merge(extra)
  end

  def helper(*arguments, extra: {})
    stdout, stderr, status = Open3.capture3(env(extra), "python3", SCRIPT, *arguments)
    [ status.exitstatus, (JSON.parse(stdout.lines.last.to_s) rescue {}), stderr ]
  end

  def read_json(path)
    path.file? ? JSON.parse(path.read) : {}
  end

  def eventually(seconds = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until (value = yield)
      flunk "timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    value
  end

  def session(id, prompt: "Call the lookup tool.", mode: "api_key", extra: {})
    directory = @root.join("claude", "sessions", id.to_s)
    directory.mkpath
    directory.chmod(0o700)
    directory.join("request.json").write(JSON.generate(
      argv: [ "claude", "-p", "--output-format", "stream-json", "--verbose" ], mode: mode, timeout: 30,
      env: { "ACTION_AGENT_SANDBOX_SESSION_ID" => "fixture" },
      pathspecs: [ ":(exclude,glob,icase)**/.credentials.json" ]
    ))
    directory.join("prompt.txt").write(prompt)
    [ directory, *helper("session-start", "--dir", directory.to_s, extra: extra) ]
  end

  test "a session runs the CLI with the prompt on stdin, records its events and the checkout's diff" do
    directory, exit_status, output = session(7, extra: { "ANTHROPIC_API_KEY" => "sk-ant-api03-fixture", "LEAKED" => "x" })
    assert_equal 0, exit_status
    assert_equal "started", output["status"]

    status = eventually { (state = read_json(directory.join("status.json")))["status"] == "finished" && state }
    assert_equal 0, status["exit_status"]
    refute status["cancelled"]
    events = directory.join("events.jsonl").readlines.map { |line| JSON.parse(line) }
    assert_equal %w[system result], events.map { |event| event["type"] }
    assert_includes directory.join("diff.patch").read, "+# fixed: Call the lookup tool."
    refute directory.join("prompt.txt").exist?, "the prompt is deleted once the CLI has it"
    assert_match(/session key=present config=.*\/api\z/, @bin.join("calls.log").read.strip)
  end

  test "a subscription session gets no Anthropic credential, and refuses project overrides" do
    _directory, exit_status, output = session(6, mode: "sandbox_login")
    assert_equal 2, exit_status
    assert_match(/no Claude subscription login/, output["error"])

    @home.join("login").mkpath
    directory, exit_status, = session(8, mode: "sandbox_login", extra: { "ANTHROPIC_API_KEY" => "sk-ant-api03-fixture" })
    assert_equal 0, exit_status
    eventually { read_json(directory.join("status.json"))["status"] == "finished" }
    assert_match(/session key=absent config=.*\/login\z/, @bin.join("calls.log").read.strip)

    @app.join(".claude").mkpath
    @app.join(".claude", "settings.json").write(JSON.generate(apiKeyHelper: "echo sk-ant-api03-other"))
    _directory, exit_status, output = session(9, mode: "sandbox_login")
    assert_equal 2, exit_status
    assert_match(/authentication overrides/, output["error"])
  end

  test "cancel stops a running session and it still records what it changed" do
    directory, = session(11, prompt: "hang")
    eventually { read_json(directory.join("status.json"))["status"] == "running" }
    eventually { directory.join("events.jsonl").size.positive? }
    exit_status, output = helper("session-cancel", "--dir", directory.to_s)
    assert_equal 0, exit_status
    assert_equal "cancelling", output["status"]
    status = eventually(15) { (state = read_json(directory.join("status.json")))["status"] == "finished" && state }
    assert status["cancelled"]
    assert_includes directory.join("diff.patch").read, "hang"
  end

  test "a session directory must be one of the sandbox's own, and a second session waits for the first" do
    exit_status, output = helper("session-start", "--dir", @root.join("elsewhere").to_s)
    assert_equal 2, exit_status
    assert_match(/not a session directory/, output["error"])

    directory, = session(12, prompt: "hang")
    eventually { read_json(directory.join("status.json"))["status"] == "running" }
    _second, exit_status, output = session(13)
    assert_equal 2, exit_status
    assert_match(/session 12 is still running/, output["error"])
    helper("session-cancel", "--dir", directory.to_s)
    eventually(15) { read_json(directory.join("status.json"))["status"] == "finished" }
  end

  test "a login gives the authorize URL, takes the code once through the pipe, and logs out" do
    home = @home
      exit_status, output = helper("login-start", "--timeout", "30")
      assert_equal 0, exit_status
      assert_equal "starting", output["status"]
      status = eventually { (state = helper("login-status")[1])["status"] == "awaiting_code" && state }
      assert_equal "https://claude.ai/oauth/authorize?code=true&client_id=fixture&state=synthetic", status["authorize_url"]

      exit_status, output = helper("login-code", extra: { "CLAUDE_LOGIN_CODE" => "one use code" })
      assert_equal 2, exit_status, "a code with whitespace is refused before it reaches the CLI"
      exit_status, output = helper("login-code", extra: { "CLAUDE_LOGIN_CODE" => "one-use-code" })
      assert_equal 0, exit_status, output.inspect
      exit_status, = helper("login-code", extra: { "CLAUDE_LOGIN_CODE" => "one-use-code" })
      assert_equal 2, exit_status, "the code goes in once"

      status = eventually { (state = helper("login-status")[1])["status"] == "connected" && state }
      assert_equal({ "status" => "connected", "logged_in" => true, "auth_method" => "claude.ai" }, status)
      refute_includes @root.join("claude").glob("**/*").select(&:file?).map(&:read).join, "one-use-code"

      exit_status, output = helper("logout")
      assert_equal 0, exit_status
      assert_equal false, output["logged_in"]
      assert_match(/logout .*\/login/, @bin.join("calls.log").read)
      refute home.join("login").exist?
      assert_equal "disconnected", helper("login-status")[1]["status"]
  end

  test "a wrong code fails the sign-in and leaves no configuration behind" do
    home = @home
      helper("login-start", "--timeout", "30")
      eventually { helper("login-status")[1]["status"] == "awaiting_code" }
      helper("login-code", extra: { "CLAUDE_LOGIN_CODE" => "not-the-code" })
      status = eventually { (state = helper("login-status")[1])["status"] == "failed" && state }
      assert_equal false, status["logged_in"]
      refute home.join("login").exist?
  end
end
