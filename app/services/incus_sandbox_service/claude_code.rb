# frozen_string_literal: true

class IncusSandboxService
  # Claude Code in an app_runtime container: headless sessions, the user's own
  # Claude subscription login, and the app restart that makes an edit live.
  # These are the engine's optional orchestrator verbs (code_session,
  # cancel_code_session, the four login verbs and refresh_runtime), so with
  # them the engine's fix loop and :sandbox_login run on Incus as they do on
  # the :local backend.
  #
  # Everything runs through the image's sandbox-claude, as root, by the
  # instance exec API. It runs the CLI as the image's `claude` user, whose
  # home (and the login in it) the checkout's own processes cannot read.
  # A session detaches; its stream-json is read back from the container with
  # Range requests, as boot logs are. A credential reaches the container only
  # as an exec's environment, never instance config, files or argv, and the
  # one-time login code only as login-code's.
  module ClaudeCode
    HELPER = "sandbox-claude"
    CLAUDE_DIR = "/workspace/claude"
    SESSIONS_DIR = "#{CLAUDE_DIR}/sessions".freeze
    LOGIN_STATUS_PATH = "#{CLAUDE_DIR}/login/status.json".freeze
    LOGIN_CONFIG = "/home/claude/login"
    EVENTS_PAGE_BYTES = 256 * 1024
    STDERR_TAIL_BYTES = 64 * 1024
    MAX_DIFF_BYTES = 1_000_000
    SESSION_POLL_INTERVAL = 1
    # How long past claude_code_timeout a session may take to end: the
    # helper stops it at the timeout and then diffs the checkout.
    SESSION_FINISH_GRACE = 120
    HELPER_TIMEOUT = 60
    LOGIN_STATES = %w[starting awaiting_code submitted completed failed expired cancelled connected disconnected].freeze
    AUTHORIZE_URL = %r{\Ahttps://(?:claude\.ai|platform\.claude\.com)/oauth/authorize\?[^\s]+\z}
    LOGIN_CODE = /\A[^\s\x00-\x1f\x7f]{1,2048}\z/
    CONTAINER_NAME = /\A#{IncusSandboxService::CONTAINER_PREFIX}-[A-Za-z0-9-]{1,60}\z/
    DISCONNECTED = { status: "disconnected", logged_in: false, auth_method: nil }.freeze

    def code_runners
      %w[claude_code]
    end

    # Runs Claude Code headless in the sandbox's checkout, yielding each
    # stream-json event (a Hash, scrubbed of the sandbox's secrets) as it
    # is read back, as the engine's LocalSandboxBackend#run_code_session does.
    #
    # @return [Hash] { exit_status:, diff:, stderr_tail: }
    def run_code_session(sandbox, code_session, &on_event)
      container = container_for!(sandbox)
      subscription = code_session.try(:credential_mode) == "sandbox_login"
      credentials = subscription ? {} : claude_credentials(sandbox)
      secrets = [ *session_secrets(sandbox), *credentials.values ].compact.map(&:to_s)
      directory = "#{SESSIONS_DIR}/#{Integer(code_session.id)}"
      timeout = ActionAgent.claude_code_timeout.to_i.clamp(60, 6 * 3600)

      [ CLAUDE_DIR, SESSIONS_DIR, directory ].each { |path| ensure_root_directory(container, path) }
      write_container_file(container, "#{directory}/request.json", JSON.generate(
        argv: claude_argv(code_session), mode: subscription ? "sandbox_login" : "api_key", timeout: timeout,
        env: { "ACTION_AGENT_SANDBOX_SESSION_ID" => sandbox.session_id },
        pathspecs: ActionAgent::SandboxCredentialPaths.pathspecs, max_diff_bytes: MAX_DIFF_BYTES
      ))
      # The prompt goes in a root-only file the helper deletes once the CLI
      # has it on stdin: never argv, which every process in the container sees.
      write_container_file(container, "#{directory}/prompt.txt", code_session.prompt.to_s)
      helper!(container, "session-start", "--dir", directory, environment: credentials, secrets: secrets)

      status = follow_session(container, directory, timeout, secrets, &on_event)
      {
        exit_status: Integer(status["exit_status"], exception: false) || 1,
        diff: ActionAgent::SecretScrubber.scrub(
          read_container_file(container, "#{directory}/diff.patch", limit: MAX_DIFF_BYTES + 4096, owner: 0).to_s
            .dup.force_encoding(Encoding::UTF_8).scrub, secrets
        ),
        stderr_tail: stderr_tail(container, directory, status, secrets)
      }
    end

    # Stops a running session: SIGTERM to its process group now, SIGKILL
    # from the helper once its grace has passed. run_code_session then
    # finishes with what the session left.
    def cancel_code_session(sandbox, code_session)
      container = container_for(sandbox) or return true
      helper(container, "session-cancel", "--dir", "#{SESSIONS_DIR}/#{Integer(code_session.id)}")
      true
    end

    # Restarts the app on the changed checkout: sandbox-app-boot --restart
    # reruns the manifest and the start, then the app must answer on the
    # container's address again. The project's secrets are passed again,
    # since their values are never kept in the container. A restart that
    # loses the app fails the sandbox, as a failed boot does, rather than
    # leave it ready with nothing listening.
    def refresh_runtime(sandbox)
      container = container_for!(sandbox)
      spec = read_boot_json(container, IncusSandboxService::BOOT_SPEC_PATH)
      raise ContainerError, "Sandbox #{sandbox.session_id} has no boot spec to restart from" unless spec.is_a?(Hash)

      available = (sandbox.try(:project)&.boot_spec(sandbox)&.to_h || {})["secrets"].to_h.transform_keys(&:to_s)
      names = Array(spec["secret_names"]).map(&:to_s)
      missing = names - available.keys
      raise ContainerError, "Restarting the app needs its project secrets again: #{missing.join(", ")}" if missing.any?

      environment = available.slice(*names).transform_values(&:to_s)
      secrets = [ *environment.values, *session_secrets(sandbox) ]
      result = exec_command(container, [ IncusSandboxService::BOOT_COMMAND, "--spec", IncusSandboxService::BOOT_SPEC_PATH, "--restart" ],
        environment: environment, timeout: Integer(spec["timeout"] || 600) + 60)
      unless result[:exit_code].to_i.zero?
        problem = ActionAgent::SecretScrubber.scrub(result[:stderr].to_s.strip.last(4_000).presence ||
          "#{IncusSandboxService::BOOT_COMMAND} --restart exited #{result[:exit_code]}", secrets)
        sandbox.update!(status: :failed, error_message: "The app did not restart after the change: #{problem}".truncate(1000)) if result[:exit_code].to_i == 1
        raise ContainerError, problem
      end

      manifest = ActionAgent::SandboxManifest.parse(read_container_file(container, IncusSandboxService::RUNTIME_MANIFEST))
      container_ip = wait_for_container_ready(container, require_service: false)
      wait_for_mcp!(container_ip, manifest["mcp_path"])
      sandbox.update!(runtime_mcp_url: "http://#{container_ip}:#{BootSpec::LISTEN_PORT}#{manifest.fetch("mcp_path")}",
        runtime_mcp_token: manifest["mcp_token"])
      true
    rescue ActionAgent::SandboxManifest::Error => e
      raise ContainerError, "#{IncusSandboxService::RUNTIME_MANIFEST}: #{e.message}"
    end

    # Starts the unmodified `claude auth login` in the sandbox. The flow's
    # state, and the authorize URL once the CLI prints it, are what
    # #claude_login_status reports.
    def start_claude_login(sandbox)
      container = container_for!(sandbox)
      timeout = (ActionAgent.try(:claude_code_login_timeout) || 300).to_i.clamp(1, 600)
      login_answer(helper!(container, "login-start", "--timeout", timeout.to_s))
    end

    # Writes the one-time code once to the waiting CLI. The code travels as
    # login-code's exec environment and nowhere else.
    def submit_claude_login_code(sandbox, code)
      raise ContainerError, "Paste the single-use code from Claude's authorization page" unless code.is_a?(String) && LOGIN_CODE.match?(code)

      container = container_for!(sandbox)
      login_answer(helper!(container, "login-code", environment: { "CLAUDE_LOGIN_CODE" => code }, secrets: [ code ]))
    end

    # The sign-in flow's state, or once none is under way whether the CLI is
    # logged in with a Claude subscription: { status:, logged_in:,
    # auth_method:, authorize_url: }, never anything else the CLI says.
    def claude_login_status(sandbox)
      container = container_for(sandbox) or return DISCONNECTED.dup
      login_answer(helper!(container, "login-status"))
    end

    # Logs the CLI out, which revokes the login, and removes its
    # configuration.
    def claude_logout(sandbox)
      container = container_for(sandbox) or return true
      helper(container, "logout")
      true
    end

    private

    # The sandbox's container: the handle the engine recorded, or the one
    # labelled with its session id.
    def container_for(sandbox)
      name = sandbox.try(:cloud_run_job_id).presence || handle_for(sandbox)
      name if name.is_a?(String) && CONTAINER_NAME.match?(name)
    end

    def container_for!(sandbox)
      container_for(sandbox) or raise ContainerNotFoundError, "Sandbox #{sandbox.session_id} has no container"
    end

    # Creates +path+ as root's, 0700. The first two levels exist from the
    # sandbox's first session on, and a daemon may refuse to create a
    # directory that is already there; a real failure shows up as the write
    # into it failing.
    def ensure_root_directory(container, path)
      write_container_file(container, path, nil, type: "directory", mode: "0700")
    rescue Faraday::Error => e
      Rails.logger.debug { "[IncusSandboxService] #{path} in #{container}: #{e.class}" }
    end

    def claude_credentials(sandbox)
      credentials = sandbox.runtime_environment.to_h.transform_keys(&:to_s).slice("ANTHROPIC_API_KEY")
      raise ContainerError, "Claude Code is not connected: connect an Anthropic API key in Settings → Integrations" if credentials.empty?

      credentials
    end

    def claude_argv(code_session)
      argv = [ "claude", "-p", "--output-format", "stream-json", "--verbose",
               "--permission-mode", ActionAgent.claude_code_permission_mode.to_s, "--no-session-persistence" ]
      argv += [ "--max-turns", ActionAgent.claude_code_max_turns.to_i.to_s ] if ActionAgent.claude_code_max_turns.present?
      if (model = code_session.try(:model).presence)
        raise ContainerError, "#{model.inspect} is not a model name" unless ActionAgent::LocalSandboxBackend::MODEL_NAME.match?(model.to_s)

        argv += [ "--model", model.to_s ]
      end
      argv
    end

    # Reads the session's events as they are written until the helper
    # records how it ended, and returns that record.
    def follow_session(container, directory, timeout, secrets)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout + SESSION_FINISH_GRACE
      offset = 0
      pending = +""
      loop do
        status = read_boot_json(container, "#{directory}/status.json") || {}
        page = read_container_range(container, "#{directory}/events.jsonl", offset, EVENTS_PAGE_BYTES, owner: 0)
        if page && !page[:data].empty?
          offset += page[:data].bytesize
          pending << page[:data]
          *lines, pending = pending.split("\n", -1)
          lines.each { |line| emit_event(line, secrets) { |event| yield event if block_given? } }
        end
        drained = page.nil? || offset >= page[:size]
        if status["status"] == "finished" && drained
          emit_event(pending, secrets) { |event| yield event if block_given? }
          return status
        end
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          raise ContainerError, "Claude Code did not finish within #{timeout}s and was stopped"
        end

        sleep(drained ? SESSION_POLL_INTERVAL : 0)
      end
    end

    def emit_event(line, secrets)
      return if line.blank?

      event = JSON.parse(line.dup.force_encoding(Encoding::UTF_8).scrub)
      yield ActionAgent::SecretScrubber.scrub(event, secrets) if event.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    def stderr_tail(container, directory, status, secrets)
      path = "#{directory}/stderr.log"
      size = read_container_range(container, path, 0, 1, owner: 0)&.dig(:size).to_i
      page = read_container_range(container, path, [ size - STDERR_TAIL_BYTES, 0 ].max, STDERR_TAIL_BYTES, owner: 0)
      text = [ page&.dig(:data).to_s.dup.force_encoding(Encoding::UTF_8).scrub.lines.last(20).join, status["error"] ].compact.join("\n")
      ActionAgent::SecretScrubber.scrub(text.strip, secrets)
    end

    # Runs the helper and returns the JSON it printed, raising with its
    # refusal (a fixed message, never the CLI's output) when it refused.
    def helper!(container, *arguments, environment: {}, secrets: [])
      result = exec_command(container, [ HELPER, *arguments ], environment: environment, timeout: HELPER_TIMEOUT)
      answer = parse_helper(result[:stdout])
      return answer if result[:exit_code].to_i.zero?

      problem = answer["error"].presence || "#{HELPER} #{arguments.first} exited #{result[:exit_code]}"
      raise ContainerError, ActionAgent::SecretScrubber.scrub(problem.to_s.truncate(500), secrets)
    end

    def helper(container, *arguments)
      helper!(container, *arguments)
    rescue StandardError => e
      Rails.logger.warn("[IncusSandboxService] #{HELPER} #{arguments.first} in #{container}: #{e.class}")
      nil
    end

    def parse_helper(stdout)
      data = JSON.parse(stdout.to_s.lines.last.to_s)
      data.is_a?(Hash) ? data : {}
    rescue JSON::ParserError
      {}
    end

    def login_answer(data)
      status = LOGIN_STATES.include?(data["status"]) ? data["status"] : "failed"
      connected = status == "connected" && data["logged_in"] == true && data["auth_method"] == "claude.ai"
      answer = { status: connected ? "connected" : (status == "connected" ? "completed" : status),
                 logged_in: connected, auth_method: connected ? "claude.ai" : nil }
      url = data["authorize_url"]
      answer[:authorize_url] = url if status == "awaiting_code" && url.is_a?(String) && AUTHORIZE_URL.match?(url)
      answer
    end

    # Logs a subscription login out before its container goes, so the login
    # is revoked rather than left valid on a deleted disk.
    def revoke_claude_login(container_name)
      return unless CONTAINER_NAME.match?(container_name.to_s)

      response = build_connection.get("/1.0/instances/#{container_name}/files", { "path" => LOGIN_CONFIG, "project" => @project })
      return unless response.headers["X-Incus-Type"] == "directory"

      helper(container_name, "logout")
    rescue StandardError
      nil
    end
  end
end
