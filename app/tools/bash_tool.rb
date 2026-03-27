# frozen_string_literal: true

# BashTool - Sandboxed command execution
#
# Executes shell commands within a restricted environment. Commands
# are validated against an allowlist and executed with timeouts
# to prevent runaway processes.
#
# Usage:
#   BashTool.call(command: "echo 'hello world'")
#   BashTool.call(command: "git status", working_directory: "my_project")
#
class BashTool < BaseTool
  tool_name "bash"
  description "Execute shell commands in a sandboxed environment. Commands are restricted to an allowlist for safety."

  parameter :command, type: "string", description: "The shell command to execute", required: true
  parameter :working_directory, type: "string", description: "Working directory relative to the sandbox root"
  parameter :timeout, type: "integer", description: "Timeout in seconds (max 60)", default: 30

  SANDBOX_ROOT = Rails.root.join("tmp", "agent_sandbox")
  MAX_OUTPUT_SIZE = 65_536 # 64KB
  MAX_TIMEOUT = 60 # seconds

  # Commands that are allowed to execute
  ALLOWED_COMMANDS = %w[
    echo cat head tail wc sort uniq grep awk sed
    ls find tree stat file
    git npm yarn bundle rake rails
    curl wget
    python python3 ruby node
    date whoami pwd env printenv
    mkdir cp mv rm touch chmod
    tar gzip gunzip zip unzip
    diff patch
    jq yq
  ].freeze

  # Patterns that are never allowed (even within allowed commands)
  BLOCKED_PATTERNS = [
    /\brm\s+-rf\s+\//, # rm -rf /
    />\s*\/dev\//, # redirect to /dev
    /\bdd\b/, # dd command
    /\bmkfs\b/, # filesystem formatting
    /\bsudo\b/, # privilege escalation
    /\bchmod\s+[0-7]*777/, # world-writable permissions
    /\b(nc|netcat|ncat)\b/, # network tools
    /\|\s*sh\b/, # piping to shell
    /\|\s*bash\b/, # piping to bash
    /`.*`/, # backtick command substitution in dangerous contexts
    /\$\(.*\bsh\b/, # command substitution with shell
  ].freeze

  def call(command:, working_directory: nil, timeout: 30)
    validate_command!(command)
    timeout = [timeout.to_i, MAX_TIMEOUT].min
    timeout = 5 if timeout <= 0

    cwd = resolve_working_directory(working_directory)
    FileUtils.mkdir_p(cwd)

    stdout, stderr, status = execute_command(command, cwd, timeout)

    {
      command: command,
      stdout: truncate_output(stdout),
      stderr: truncate_output(stderr),
      exit_code: status.exitstatus,
      success: status.success?,
      truncated: stdout.length > MAX_OUTPUT_SIZE || stderr.length > MAX_OUTPUT_SIZE,
      executed_at: Time.current.iso8601
    }
  end

  private

  def validate_command!(command)
    # Extract the base command (first word)
    base_command = command.strip.split(/\s+/).first&.split("/")&.last

    unless ALLOWED_COMMANDS.include?(base_command)
      raise ParameterError, "Command not allowed: #{base_command}. Allowed commands: #{ALLOWED_COMMANDS.join(', ')}"
    end

    BLOCKED_PATTERNS.each do |pattern|
      if command.match?(pattern)
        raise ParameterError, "Command contains blocked pattern: #{command}"
      end
    end
  end

  def resolve_working_directory(relative_path)
    FileUtils.mkdir_p(SANDBOX_ROOT)

    if relative_path.present?
      full_path = File.expand_path(relative_path, SANDBOX_ROOT)
      unless full_path.start_with?(SANDBOX_ROOT.to_s)
        raise ParameterError, "Working directory must be within the sandbox"
      end
      full_path
    else
      SANDBOX_ROOT.to_s
    end
  end

  def execute_command(command, cwd, timeout)
    require "open3"

    # Set restrictive environment
    env = {
      "HOME" => SANDBOX_ROOT.to_s,
      "PATH" => "/usr/local/bin:/usr/bin:/bin",
      "LANG" => "en_US.UTF-8"
    }

    stdout = ""
    stderr = ""
    status = nil

    begin
      Timeout.timeout(timeout) do
        stdout, stderr, status = Open3.capture3(env, command, chdir: cwd)
      end
    rescue Timeout::Error
      raise ExecutionError, "Command timed out after #{timeout}s: #{command}"
    end

    [stdout, stderr, status]
  end

  def truncate_output(output)
    if output.length > MAX_OUTPUT_SIZE
      output[0...MAX_OUTPUT_SIZE] + "\n... (output truncated)"
    else
      output
    end
  end
end
