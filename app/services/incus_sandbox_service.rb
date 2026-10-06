# frozen_string_literal: true

# IncusSandboxService
#
# Cloud-agnostic container orchestration using Incus (LXD fork).
# Works on any Linux host - self-hosted, DigitalOcean, Linode, Hetzner, etc.
#
# Setup:
#   1. Install Incus on your server: apt install incus
#   2. Initialize: incus admin init
#   3. Configure remote access for Rails app
#
# Usage:
#   service = IncusSandboxService.new
#   container = service.create_sandbox(sandbox_session)
#   status = service.container_status(container_name)
#   service.terminate(container_name)
#
# An app_runtime session (a checkout of one of the account's GitHub
# repositories) boots from the sandbox-app-runtime image, built by
# scripts/build-app-runtime-image.sh from docker/sandbox/app-runtime. The
# repository is fetched into APP_DIR as the image's unprivileged user, the
# boot is resolved into a boot spec (BootSpec) written into the container, and
# the image's BOOT_COMMAND runs it: each step with its own timeout and log,
# then the app on :8080, which is ready once the MCP path of the runtime
# manifest it writes answers. Secrets reach the boot only as exec environment,
# never instance config, files or argv.
#
class IncusSandboxService
  CONTAINER_PREFIX = "sandbox"
  DEFAULT_TIMEOUT = 900 # 15 minutes
  POLL_INTERVAL = 1 # seconds

  APP_RUNTIME_IMAGE = "sandbox-app-runtime"
  # The image's /workspace is root's. The sandbox user owns APP_DIR, and the
  # boot creates RUNTIME_DIR and BootSpec::DATA_DIR for it. BOOT_DIR is root's
  # alone, because sandbox-app-boot runs as root from what it holds.
  APP_DIR = "/workspace/app"
  BOOT_COMMAND = "sandbox-app-boot"
  RUNTIME_DIR = "/workspace/run"
  RUNTIME_MANIFEST = "#{RUNTIME_DIR}/runtime.json"
  BOOT_DIR = "/workspace/boot"
  BOOT_SPEC_PATH = "#{BOOT_DIR}/spec.json"
  BOOT_STATE_PATH = "#{BOOT_DIR}/state.json"
  # The version of the boot spec this service writes. The image records the
  # version its sandbox-app-boot runs as the image property
  # boot_spec_version, and the two must match.
  BOOT_SPEC_VERSION = 1
  # The image's user, which owns APP_DIR and runs every boot command.
  SANDBOX_UID = 1000
  STORAGE_POOL = "default"
  CHECKOUT_TIMEOUT = 300
  # A GET on the MCP path answers 405 once the engine is mounted and serving;
  # 401 and 200 also mean something is up and answering there.
  READY_STATUSES = [ 405, 401, 200 ].freeze
  # How long the app may take to answer on the container's address once
  # sandbox-app-boot saw it answer inside.
  OUTSIDE_READY_TIMEOUT = 30
  MAX_FILE_BYTES = 256 * 1024
  LOG_PAGE_BYTES = 64 * 1024
  MAX_LOG_PAGE_BYTES = 1024 * 1024
  LOG_NAME = /\A[a-z][a-z0-9_]{0,39}\z/
  OPERATION_TIMED_OUT = "Operation timed out"
  # How long one long-poll of an operation lasts, inside the connection's
  # 30-second read timeout.
  OPERATION_WAIT_SECONDS = 20

  # The per-environment switch for checkout sandboxes, set by Terraform
  # (incus_app_runtime_enabled). It stays off until the environment's Incus
  # host has its egress controls.
  APP_RUNTIME_SWITCH = "INCUS_APP_RUNTIME_ENABLED"
  APP_RUNTIME_CACHE_KEY = "incus_sandbox_service/app_runtime_available"

  # Fetches exactly the requested ref (branch, tag, or commit). Git gets the
  # token through GIT_CONFIG_* for the one fetch: never in argv, which every
  # process in the container can read, and never in .git/config, which the
  # checked-out app can. No credential helper is asked.
  CHECKOUT_SCRIPT = <<~'SH'
    set -eu
    git init -q "$APP_DIR"
    cd "$APP_DIR"
    git remote add origin "$CHECKOUT_URL"
    header="Authorization: Basic $(printf '%s:%s' "$CHECKOUT_USER" "$CHECKOUT_TOKEN" | base64 | tr -d '\n')"
    unset CHECKOUT_TOKEN
    GIT_CONFIG_COUNT=2 \
      GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
      GIT_CONFIG_KEY_1=http.extraHeader GIT_CONFIG_VALUE_1="$header" \
      git fetch -q --depth 1 origin "$CHECKOUT_REF"
    git checkout -q --detach FETCH_HEAD
  SH

  class ContainerError < StandardError; end
  class ContainerNotFoundError < StandardError; end
  class ConnectionError < StandardError; end

  def initialize(config = {})
    @host = config[:host] || ENV.fetch("INCUS_HOST", "unix:///var/lib/incus/unix.socket")
    @cert_path = config[:cert_path] || ENV["INCUS_CERT_PATH"]
    @key_path = config[:key_path] || ENV["INCUS_KEY_PATH"]
    @server_ca_path = config[:server_ca_path] || ENV["INCUS_SERVER_CA_PATH"]
    @project = config[:project] || ENV.fetch("INCUS_PROJECT", "agent-sandboxes")
  end

  # Whether checkout sandboxes are switched on in this environment
  # (APP_RUNTIME_SWITCH).
  def self.app_runtime_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV[APP_RUNTIME_SWITCH]) == true
  end

  # Whether this platform can boot checkouts: the switch is on, and the daemon
  # carries the app-runtime image at the boot spec version this service
  # writes. The daemon's answer is cached, for five minutes when it is yes and
  # one when it is no, so a rebuilt image is noticed soon.
  #
  # The dashboard reads it through #features, the hook the engine's sandbox
  # orchestrator asks a backend to describe itself with.
  #
  # @param service [IncusSandboxService, nil] the client to ask the daemon
  #   through; a new one when nil
  def self.app_runtime_available?(service: nil)
    return false unless app_runtime_enabled?

    cached = Rails.cache.read(APP_RUNTIME_CACHE_KEY)
    return cached unless cached.nil?

    supported = begin
      (service || new).app_runtime_image[:supported]
    rescue StandardError => e
      Rails.logger.warn("[IncusSandboxService] could not check the app-runtime image: #{e.message}")
      false
    end
    Rails.cache.write(APP_RUNTIME_CACHE_KEY, supported, expires_in: supported ? 5.minutes : 1.minute)
    supported
  end

  # Create a new sandbox container for the given session
  #
  # An app_runtime session boots its checkout as +boot_config+ says (the
  # engine's ActionAgent::SandboxBootSpec#to_h), or as the checkout's own
  # .activeagents/sandbox.yml does without one (see BootSpec). A failed boot
  # whose spec asks to keep_on_failure keeps its container, so #resume_boot
  # can continue it; any other failure removes it.
  #
  # @param sandbox_session [SandboxSession] The session to create a container for
  # @param instance_tier [SandboxInstanceTier, String, nil] Optional instance tier for resource allocation
  # @param boot_config [Hash, nil] how to boot an app_runtime checkout
  # @return [Hash] Container details including name and IP
  # @raise [ContainerError] when the container cannot be created or booted, or
  #   checkout sandboxes are switched off
  def create_sandbox(sandbox_session, instance_tier: nil, boot_config: nil)
    app_runtime = sandbox_session.sandbox_type == "app_runtime"
    if app_runtime && !self.class.app_runtime_enabled?
      raise ContainerError, "Checkout sandboxes are switched off on this platform (#{APP_RUNTIME_SWITCH})"
    end

    container_name = generate_container_name(sandbox_session.session_id)
    tier = resolve_instance_tier(instance_tier, sandbox_session)
    timeout = sandbox_session.timeout_seconds || DEFAULT_TIMEOUT

    config = build_container_config(
      name: container_name,
      session_id: sandbox_session.session_id,
      # The engine's sessions answer #owner (Ownable), not #owner_id.
      owner_id: sandbox_session.try(:owner)&.id,
      sandbox_type: sandbox_session.sandbox_type,
      timeout: timeout,
      expires_at: sandbox_session.try(:expires_at) || timeout.seconds.from_now,
      instance_tier: tier
    )

    secrets = []
    keep = false
    begin
      response = api_request(:post, "/1.0/instances", config)
      wait_for_operation(response["operation"]) if response["operation"]

      start_response = api_request(:put, "/1.0/instances/#{container_name}/state", {
        action: "start",
        timeout: 30
      })
      wait_for_operation(start_response["operation"]) if start_response["operation"]

      # A checkout has nothing listening until it is fetched and booted, so
      # only the network is awaited before that.
      checkout = sandbox_session.try(:checkout_spec)
      container_ip = wait_for_container_ready(container_name, require_service: checkout.nil?)
      runtime = nil
      if checkout
        secrets = [ checkout[:token], *boot_config_secrets(boot_config), *session_secrets(sandbox_session) ]
        boot = prepare_boot(container_name, sandbox_session, checkout, boot_config)
        # From here on the container holds everything a resume needs.
        keep = boot.keep_on_failure?
        runtime = run_boot(container_name, container_ip, boot, secrets)
      end

      {
        mcp_url: runtime && "http://#{container_ip}:#{BootSpec::LISTEN_PORT}#{runtime.fetch("mcp_path")}",
        mcp_token: runtime&.dig("mcp_token"),
        container_name: container_name,
        container_ip: container_ip,
        url: "http://#{container_ip}:8080",
        project: @project,
        created_at: Time.current,
        instance_tier: tier.id,
        resources: {
          cpu_cores: tier.cpu_cores,
          memory_gb: tier.memory_gb,
          gpu: tier.gpu
        },
        hourly_cost: tier.hourly_cost.to_f
      }
    rescue => e
      terminate(container_name) unless keep
      message = ActionAgent::SecretScrubber.scrub(e.message, secrets)
      Rails.logger.error("Failed to create sandbox container: #{message}")
      raise ContainerError, "Failed to create sandbox: #{message}#{" (its container is kept for a resume)" if keep}"
    end
  end

  # Continues a failed boot that kept its container: reruns it from the step
  # named +from+, or from the step that failed when +from+ is nil, on the same
  # checkout and databases. Nothing is fetched again and no earlier step runs
  # again. +boot_config+ replaces the spec the boot started with, for new env
  # or secrets; without one the spec in the container is used, which holds no
  # secret values, so a boot whose spec had secrets needs it passed again.
  #
  # @return [Hash] what #create_sandbox returns, without the tier
  # @raise [ContainerNotFoundError] when the session has no container
  # @raise [ContainerError] when there is no kept boot to resume, or it fails again
  def resume_boot(sandbox_session, from:, boot_config: nil)
    session_id = sandbox_session.session_id
    container_name = handle_for(sandbox_session) or raise ContainerNotFoundError, "Sandbox #{session_id} has no container to resume"
    state = read_boot_json(container_name, BOOT_STATE_PATH)
    unless state.is_a?(Hash) && state["kept"] == true && state["status"] == "failed"
      raise ContainerError, "Sandbox #{session_id} has no failed boot kept to resume: start it again"
    end

    previous = read_boot_json(container_name, BOOT_SPEC_PATH)
    raise ContainerError, "Sandbox #{session_id} has no boot spec to resume from: start it again" unless previous.is_a?(Hash)

    checkout = begin
      sandbox_session.try(:checkout_spec)
    rescue StandardError
      nil
    end
    boot =
      if boot_config
        BootSpec.build(boot_config: boot_config, files: read_checkout_files(container_name), session_id: session_id,
          repository: checkout&.dig(:repository), previous: previous)
      else
        BootSpec.from_document(previous)
      end
    if boot.missing_secrets.any?
      raise ContainerError, "Resuming sandbox #{session_id} needs its boot spec again: the values of " \
        "#{boot.missing_secrets.join(", ")} are never kept"
    end

    step = (from.presence || state["failed_step"]).to_s
    unless boot.resumable_steps.include?(step)
      raise ContainerError, "#{step.inspect} is not a step this boot can resume from (#{boot.resumable_steps.join(", ")})"
    end

    write_container_file(container_name, BOOT_SPEC_PATH, JSON.pretty_generate(boot.document)) if boot_config
    secrets = [ checkout&.dig(:token), *boot.secrets.values, *session_secrets(sandbox_session) ]
    container_ip = wait_for_container_ready(container_name, require_service: false)
    runtime = begin
      run_boot(container_name, container_ip, boot, secrets, from: step)
    rescue ContainerError => e
      terminate(container_name) unless boot.keep_on_failure?
      raise ContainerError, "#{ActionAgent::SecretScrubber.scrub(e.message, secrets)}" \
        "#{" (its container is kept for a resume)" if boot.keep_on_failure?}"
    end

    {
      mcp_url: "http://#{container_ip}:#{BootSpec::LISTEN_PORT}#{runtime.fetch("mcp_path")}",
      mcp_token: runtime["mcp_token"],
      container_name: container_name,
      container_ip: container_ip,
      url: "http://#{container_ip}:8080",
      project: @project,
      created_at: Time.current
    }
  rescue BootSpec::Refused => e
    raise ContainerError, e.message
  end

  # How the session's boot went, step by step, while its container holds it:
  # the shape the engine's SandboxOrchestrator#boot_status documents. Nil when
  # the session has no container, or the container no boot.
  def boot_status(sandbox_session)
    container_name = handle_for(sandbox_session) or return nil
    state = read_boot_json(container_name, BOOT_STATE_PATH)
    return nil unless state.is_a?(Hash) && state["steps"].is_a?(Array)

    secrets = session_secrets(sandbox_session)
    {
      mode: state["mode"],
      kind: state["kind"],
      failed_step: state["failed_step"],
      kept: state["kept"] == true,
      resumable_steps: Array(state["resumable_steps"]).map(&:to_s),
      steps: state["steps"].filter_map do |step|
        next unless step.is_a?(Hash)

        {
          name: step["name"], status: step["status"], started_at: step["started_at"], finished_at: step["finished_at"],
          duration_ms: step["duration_ms"],
          detail: step["detail"] && ActionAgent::SecretScrubber.scrub(step["detail"].to_s, secrets)
        }
      end
    }
  end

  # One page of a boot step's log, scrubbed of the session's secrets and of
  # +secrets+ (see the engine's SandboxOrchestrator#boot_log). Pages end at a
  # line break where they can, so a value is never split between two of them.
  # Only the page is fetched from the container, so a log of any size can be
  # paged: start.log, the server's own output, grows for as long as it runs.
  #
  # @return [Hash, nil] { step:, offset:, next_offset:, size:, eof:, text: },
  #   or nil when the step has no log
  def boot_log(sandbox_session, step:, offset: 0, limit: LOG_PAGE_BYTES, secrets: [])
    container_name = handle_for(sandbox_session) or return nil
    state = read_boot_json(container_name, BOOT_STATE_PATH)
    steps = state.is_a?(Hash) && state["steps"].is_a?(Array) ? state["steps"] : []
    entry = steps.find { |candidate| candidate.is_a?(Hash) && candidate["name"] == step.to_s }
    return nil unless entry && LOG_NAME.match?(entry["log"].to_s)

    offset = [ Integer(offset, exception: false).to_i, 0 ].max
    limit = Integer(limit, exception: false).to_i.clamp(1, MAX_LOG_PAGE_BYTES)
    page = read_container_range(container_name, "#{BOOT_DIR}/logs/#{entry["log"]}.log", offset, limit, owner: 0)
    return nil if page.nil?

    size = page[:size]
    offset = [ offset, size ].min
    data = page[:data]
    if offset + data.bytesize < size && (newline = data.rindex("\n"))
      data = data.byteslice(0, newline + 1)
    end
    next_offset = offset + data.bytesize

    {
      step: entry["name"], offset: offset, next_offset: next_offset, size: size, eof: next_offset >= size,
      text: ActionAgent::SecretScrubber.scrub(data.dup.force_encoding(Encoding::UTF_8).scrub,
        session_secrets(sandbox_session) + Array(secrets))
    }
  end

  # How this backend describes itself to the engine's sandbox orchestrator
  # (SandboxOrchestrator#backend_info). +app_runtime+ says whether checkouts
  # can boot here (see .app_runtime_available?).
  def features
    {
      cloud_agnostic: true,
      isolation: "namespaces + apparmor",
      networking: "bridge",
      persistent_storage: true,
      live_migration: true,
      self_hosted: true,
      app_runtime: self.class.app_runtime_available?(service: self),
      boot_spec_version: BOOT_SPEC_VERSION
    }
  end

  # Get the status of a sandbox container
  #
  # @param container_name [String] The container name
  # @return [Hash] Container status details
  def container_status(container_name)
    response = api_request(:get, "/1.0/instances/#{container_name}")
    instance = response["metadata"]

    state_response = api_request(:get, "/1.0/instances/#{container_name}/state")
    state = state_response["metadata"]

    {
      name: instance["name"],
      status: state["status"],
      ip: extract_ip(state),
      pid: state["pid"],
      cpu_usage: state.dig("cpu", "usage"),
      memory_usage: state.dig("memory", "usage"),
      created_at: instance["created_at"],
      config: instance["config"]
    }
  rescue Faraday::ResourceNotFound
    raise ContainerNotFoundError, "Container #{container_name} not found"
  end

  # Terminate a sandbox container
  #
  # @param container_name [String] The container name to terminate
  # @return [Boolean] true if deleted
  def terminate(container_name)
    # Stop the container first
    begin
      stop_response = api_request(:put, "/1.0/instances/#{container_name}/state", {
        action: "stop",
        timeout: 10,
        force: true
      })
      wait_for_operation(stop_response["operation"]) if stop_response["operation"]
    rescue => e
      Rails.logger.debug("Container stop failed (may already be stopped): #{e.message}")
    end

    # Delete the container
    delete_response = api_request(:delete, "/1.0/instances/#{container_name}")
    wait_for_operation(delete_response["operation"]) if delete_response["operation"]

    true
  rescue Faraday::ResourceNotFound
    true # Already deleted
  rescue => e
    Rails.logger.error("Failed to terminate container #{container_name}: #{e.message}")
    false
  end

  # The container booted for +sandbox_session+, found by the session id it
  # was labelled with. The engine asks for it when a boot's job died before
  # recording the container's name (activeagent#491), so Stop and the reaper
  # can still remove it.
  #
  # @return [String, nil] the container name
  def handle_for(sandbox_session)
    list_sandboxes.find { |sandbox| sandbox[:session_id] == sandbox_session.session_id }&.dig(:name)
  end

  # List all sandbox containers
  #
  # @return [Array<Hash>] List of container statuses
  def list_sandboxes
    response = api_request(:get, "/1.0/instances", { "recursion" => 1 })
    instances = response["metadata"] || []

    instances.select { |i| i.is_a?(Hash) && i["name"].to_s.start_with?("#{CONTAINER_PREFIX}-") }.map do |instance|
      {
        name: instance["name"],
        status: instance["status"],
        created_at: instance["created_at"],
        expires_at: instance.dig("config", "user.expires_at"),
        session_id: instance.dig("config", "user.session_id")
      }
    end
  end

  # Execute a command in a sandbox container
  #
  # @param container_name [String] The container name
  # @param command [Array<String>] Command to execute
  # @return [Hash] stdout, stderr, exit_code
  def exec_in_container(container_name, command)
    response = api_request(:post, "/1.0/instances/#{container_name}/exec", {
      command: command,
      "wait-for-websocket": false,
      interactive: false,
      "record-output": true
    })

    operation = wait_for_operation(response["operation"])
    metadata = operation.fetch("metadata")
    output = metadata.fetch("output", {})
    {
      stdout: recorded_output(container_name, output["1"]),
      stderr: recorded_output(container_name, output["2"]),
      exit_code: metadata.fetch("return")
    }
  end

  # Get logs from a sandbox container
  #
  # @param container_name [String] The container name
  # @param log_file [String] Log file to read (default: /var/log/sandbox.log)
  # @return [String] Log contents
  def container_logs(container_name, log_file: "/var/log/sandbox.log")
    result = exec_in_container(container_name, [ "cat", log_file ])
    raise ContainerError, "Reading the sandbox log exited with status #{result[:exit_code]}" unless result[:exit_code] == 0

    result[:stdout]
  rescue => e
    Rails.logger.warn("Failed to get logs for #{container_name}: #{e.message}")
    ""
  end

  # Removes the sandbox containers whose time is up: past the user.expires_at
  # copied from their session, or DEFAULT_TIMEOUT after creation for one
  # without it. The hosts' cron reaper (scripts/incus/cleanup-sandboxes.sh)
  # applies the same rule.
  #
  # @return [Integer] Number of containers cleaned up
  def cleanup_expired
    sandboxes = list_sandboxes
    cleaned = 0

    sandboxes.each do |sandbox|
      deadline = expiry_of(sandbox)
      next unless deadline && Time.current > deadline

      terminate(sandbox[:name])
      cleaned += 1
      Rails.logger.info("Cleaned up expired sandbox: #{sandbox[:name]}")
    end

    cleaned
  end

  # Ensure the sandbox project exists
  #
  # @return [Boolean] true if project exists or was created
  def ensure_project
    begin
      api_request(:get, "/1.0/projects/#{@project}")
      true
    rescue Faraday::ResourceNotFound
      api_request(:post, "/1.0/projects", {
        name: @project,
        description: "Agent sandbox containers",
        config: {
          "features.images" => "true",
          "features.profiles" => "true"
        }
      })
      true
    end
  end

  # Create sandbox profile with security settings
  #
  # @return [Boolean] true if profile exists or was created
  def ensure_sandbox_profile
    profile_name = "sandbox-restricted"

    begin
      api_request(:get, "/1.0/profiles/#{profile_name}")
      true
    rescue Faraday::ResourceNotFound
      api_request(:post, "/1.0/profiles", {
        name: profile_name,
        description: "Restricted profile for agent sandboxes",
        config: {
          # Security restrictions
          "security.nesting" => "false",
          "security.privileged" => "false",
          "security.idmap.isolated" => "true",

          # Resource limits
          "limits.cpu" => "2",
          "limits.memory" => "2GB",
          "limits.processes" => "500",

          # Network restrictions
          "raw.apparmor" => sandbox_apparmor_profile
        },
        devices: {
          "eth0" => {
            "name" => "eth0",
            "network" => "incusbr0",
            "type" => "nic"
          },
          "root" => {
            "path" => "/",
            "pool" => "default",
            "type" => "disk",
            "size" => "10GB"
          }
        }
      })
      true
    end
  end

  # Read-only checks before provisioning anything. Credentials never appear
  # in the report; being able to reach the daemon is not proof of trust.
  # app_runtime_supported says whether checkouts can boot: the switch is on
  # and the daemon carries the checkout image at this service's boot spec
  # version (app_runtime_image says which it has). code_sessions_supported
  # says whether this backend runs Claude Code sessions, which the
  # orchestrator decides by the presence of run_code_session.
  def preflight
    server = api_request(:get, "/1.0").fetch("metadata")
    raise ConnectionError, "Incus did not authenticate this client certificate" unless server["auth"] == "trusted"

    api_request(:get, "/1.0/projects/#{@project}")
    api_request(:get, "/1.0/profiles/sandbox-restricted")
    image = app_runtime_image
    {
      connected: true, project: @project,
      server_version: server.dig("environment", "server_version"),
      sandbox_count: list_sandboxes.size,
      app_runtime_enabled: self.class.app_runtime_enabled?,
      app_runtime_image: { present: image[:present], boot_spec_version: image[:boot_spec_version],
                           expected_boot_spec_version: BOOT_SPEC_VERSION },
      app_runtime_supported: self.class.app_runtime_enabled? && image[:supported],
      code_sessions_supported: respond_to?(:run_code_session)
    }
  end

  # The checkout image on the daemon: whether it is there, the boot spec
  # version it records, and whether that is the version this service writes.
  #
  # @return [Hash] { present:, boot_spec_version:, supported: }
  def app_runtime_image
    target = api_request(:get, "/1.0/images/aliases/#{APP_RUNTIME_IMAGE}").dig("metadata", "target")
    version = api_request(:get, "/1.0/images/#{target}").dig("metadata", "properties", "boot_spec_version")
    { present: true, boot_spec_version: version, supported: version.to_s == BOOT_SPEC_VERSION.to_s }
  rescue Faraday::ResourceNotFound
    { present: false, boot_spec_version: nil, supported: false }
  end

  private

  # Fetches the checkout as the image's user, reads the files that decide how
  # it boots, and writes the resolved boot spec into the container. The token
  # reaches the container only as the fetch's exec environment.
  #
  # @return [BootSpec]
  def prepare_boot(container_name, sandbox_session, checkout, boot_config)
    started = Time.current
    run_in_container!(container_name, [ "sh", "-c", CHECKOUT_SCRIPT ], user: SANDBOX_UID, timeout: CHECKOUT_TIMEOUT, environment: {
      "HOME" => "/home/sandbox",
      "APP_DIR" => APP_DIR,
      "CHECKOUT_URL" => checkout.fetch(:clone_url),
      "CHECKOUT_REF" => checkout.fetch(:ref),
      "CHECKOUT_USER" => checkout.fetch(:username),
      "CHECKOUT_TOKEN" => checkout.fetch(:token)
    })
    finished = Time.current
    checkout_step = { name: "checkout", status: "succeeded", started_at: started.iso8601(3), finished_at: finished.iso8601(3),
                      duration_ms: ((finished - started) * 1000).round, detail: "#{checkout[:repository]}@#{checkout[:ref]}" }

    boot = BootSpec.build(boot_config: boot_config, files: read_checkout_files(container_name),
      session_id: sandbox_session.session_id, repository: checkout[:repository], recorded_steps: [ checkout_step ])
    write_container_file(container_name, BOOT_DIR, nil, type: "directory", mode: "0700")
    write_container_file(container_name, BOOT_SPEC_PATH, JSON.pretty_generate(boot.document))
    boot
  rescue BootSpec::Refused => e
    raise ContainerError, e.message
  end

  # Runs the boot spec in the container (from step +from+ for a resume) and
  # returns the runtime manifest once the app answers on the container's
  # address. The spec's secrets are the boot's exec environment and nothing
  # else; +secrets+ are what its failure message is scrubbed of.
  def run_boot(container_name, container_ip, boot, secrets, from: nil)
    command = [ BOOT_COMMAND, "--spec", BOOT_SPEC_PATH ]
    command += [ "--from", from ] if from
    result = begin
      exec_command(container_name, command, environment: boot.secrets, timeout: boot.exec_timeout)
    rescue ContainerError => e
      raise unless e.message == OPERATION_TIMED_OUT

      raise ContainerError, "#{BOOT_COMMAND} did not finish within #{boot.exec_timeout}s"
    end
    unless result[:exit_code].to_i.zero?
      problem = result[:stderr].strip.presence || "#{BOOT_COMMAND} exited #{result[:exit_code]}"
      raise ContainerError, ActionAgent::SecretScrubber.scrub(problem.last(8_000), secrets)
    end

    manifest = ActionAgent::SandboxManifest.parse(read_container_file(container_name, RUNTIME_MANIFEST))
    wait_for_mcp!(container_ip, manifest["mcp_path"])
    manifest
  rescue ActionAgent::SandboxManifest::Error => e
    raise ContainerError, "#{RUNTIME_MANIFEST}: #{e.message}"
  end

  # Polls until the app's MCP path answers on the container's address, the
  # one agents reach it at.
  def wait_for_mcp!(container_ip, mcp_path)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + OUTSIDE_READY_TIMEOUT
    last = nil
    loop do
      status = mcp_status(container_ip, mcp_path)
      return if READY_STATUSES.include?(status)

      last = status || last
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise ContainerError, "The app answered #{mcp_path} inside the sandbox but not on #{container_ip}:#{BootSpec::LISTEN_PORT}" \
          "#{" (last answer: #{last})" if last}"
      end
      sleep POLL_INTERVAL
    end
  end

  def mcp_status(ip, path)
    Net::HTTP.start(ip, BootSpec::LISTEN_PORT, open_timeout: 2, read_timeout: 5) do |http|
      http.get(path, "Accept" => "application/json").code.to_i
    end
  rescue StandardError
    nil
  end

  # The files BootSpec decides a boot from, as checked out.
  def read_checkout_files(container_name)
    BootSpec::FILES.index_with { |path| read_container_file(container_name, "#{APP_DIR}/#{path}") }
  end

  # A JSON file the boot keeps in BOOT_DIR (its spec or its state), parsed.
  # Nil when it is missing, is not JSON, or is not root's: nothing else
  # writes there.
  def read_boot_json(container_name, path)
    content = read_container_file(container_name, path, owner: 0)
    content && JSON.parse(content)
  rescue JSON::ParserError
    nil
  end

  # Reads +path+ through the instance file API. Nil when nothing is there,
  # when it is something other than a regular file (a symlink is never
  # followed), or when +owner+ is given and another uid owns it.
  #
  # @raise [ContainerError] for a file larger than +limit+ bytes
  def read_container_file(container_name, path, limit: MAX_FILE_BYTES, owner: nil)
    response = build_connection.get("/1.0/instances/#{container_name}/files", { "path" => path, "project" => @project })
    return nil unless regular_file?(response.headers, owner)

    content = response_bytes(response.body)
    raise ContainerError, "#{path} in the sandbox is larger than #{limit} bytes" if content.bytesize > limit

    content
  rescue Faraday::ResourceNotFound
    nil
  end

  # Up to +length+ bytes of +path+ from +offset+, fetched with a Range
  # request, and the file's size. Nil as #read_container_file says.
  #
  # @return [Hash, nil] { data:, size: }
  def read_container_range(container_name, path, offset, length, owner: nil)
    response = build_connection.get("/1.0/instances/#{container_name}/files", { "path" => path, "project" => @project },
      { "Range" => "bytes=#{offset}-#{offset + length - 1}" })
    return nil unless regular_file?(response.headers, owner)

    content = response_bytes(response.body)
    if response.status == 206
      { data: content, size: range_size(response.headers) }
    else
      # A daemon that ignores Range answers with the whole file.
      { data: content.byteslice(offset, length).to_s, size: content.bytesize }
    end
  rescue Faraday::ResourceNotFound
    nil
  rescue Faraday::ClientError => e
    # 416 answers an offset at or past the end of the file.
    raise unless e.response_status == 416 && regular_file?(e.response_headers, owner)

    { data: "".b, size: range_size(e.response_headers) }
  end

  def regular_file?(headers, owner)
    headers["X-Incus-Type"] == "file" && (owner.nil? || headers["X-Incus-Uid"] == owner.to_s)
  end

  # The connection parses a body served as JSON, whatever file it came from.
  def response_bytes(body)
    (body.is_a?(String) ? body : body.to_json).b
  end

  # The file size a Content-Range header ("bytes 0-99/1234" or "bytes */1234")
  # ends with.
  def range_size(headers)
    headers["Content-Range"].to_s[%r{/(\d+)\z}, 1].to_i
  end

  # Writes +content+ to +path+ through the instance file API, owned by root:
  # what the platform writes is for sandbox-app-boot, not the app.
  def write_container_file(container_name, path, content, type: "file", mode: "0600")
    build_connection.post("/1.0/instances/#{container_name}/files") do |request|
      request.params = { "path" => path, "project" => @project }
      request.headers.update(
        "Content-Type" => "application/octet-stream", "X-Incus-Type" => type, "X-Incus-Uid" => "0",
        "X-Incus-Gid" => "0", "X-Incus-Mode" => mode, "X-Incus-Write" => "overwrite"
      )
      request.body = content.to_s
    end
  end

  # The secret values a boot spec carries, for scrubbing.
  def boot_config_secrets(boot_config)
    secrets = boot_config.is_a?(Hash) ? (boot_config[:secrets] || boot_config["secrets"]) : nil
    secrets.is_a?(Hash) ? secrets.values.map(&:to_s) : []
  end

  # What a sandbox's stored output is scrubbed of when it is read back: its
  # checkout token and the credentials its sessions get.
  def session_secrets(sandbox_session)
    token = begin
      sandbox_session.try(:checkout_spec)&.dig(:token)
    rescue StandardError
      nil
    end
    environment = begin
      sandbox_session.try(:runtime_environment).to_h
    rescue StandardError
      {}
    end
    [ token, *environment.values ].compact.map(&:to_s)
  end

  # When +sandbox+ (a #list_sandboxes entry) expires, or nil when it cannot
  # be told.
  def expiry_of(sandbox)
    expires_at = Time.iso8601(sandbox[:expires_at].to_s) if sandbox[:expires_at].present?
    expires_at || (Time.parse(sandbox[:created_at].to_s) + DEFAULT_TIMEOUT if sandbox[:created_at].present?)
  rescue ArgumentError
    nil
  end

  # Runs +command+ and returns its stdout, raising with stderr when it exits
  # non-zero.
  def run_in_container!(container_name, command, environment: {}, timeout: 120, user: nil)
    result = exec_command(container_name, command, environment: environment, timeout: timeout, user: user)
    unless result[:exit_code].to_i.zero?
      raise ContainerError, "#{command.first} exited #{result[:exit_code]}: #{result[:stderr].strip.last(500)}"
    end

    result[:stdout]
  end

  # Runs +command+ (as +user+, a uid, when given) and returns its output and
  # exit status. +environment+ is the exec's alone: Incus keeps it out of the
  # instance's configuration.
  def exec_command(container_name, command, environment: {}, timeout: 120, user: nil)
    body = {
      command: command,
      environment: environment,
      "wait-for-websocket": false,
      interactive: false,
      "record-output": true
    }
    body.merge!(user: user, group: user) if user
    response = api_request(:post, "/1.0/instances/#{container_name}/exec", body)
    operation = wait_for_operation(response["operation"], timeout: timeout)
    output = operation.dig("metadata", "output") || {}
    {
      stdout: recorded_output(container_name, output["1"]),
      stderr: recorded_output(container_name, output["2"]),
      exit_code: operation.dig("metadata", "return")
    }
  end

  # Incus records stdout/stderr as log resources, not inline strings.
  # Only fetch resources from this instance on the configured daemon.
  def recorded_output(container_name, path)
    return "" if path.blank?

    uri = URI.parse(path)
    prefix = "/1.0/instances/#{container_name}/logs/"
    unless uri.scheme.nil? && uri.host.nil? && uri.path.start_with?(prefix) && !uri.path.include?("..")
      raise ContainerError, "Incus returned an unexpected exec output URL"
    end

    api_request(:get, uri.path).to_s
  end

  def generate_container_name(session_id)
    "#{CONTAINER_PREFIX}-#{session_id[0..7]}-#{SecureRandom.hex(4)}"
  end

  def build_container_config(name:, session_id:, owner_id:, sandbox_type:, timeout:, expires_at:, instance_tier:)
    config = {
      # Metadata
      "user.session_id" => session_id,
      "user.owner_id" => owner_id.to_s,
      "user.sandbox_type" => sandbox_type,
      "user.instance_tier" => instance_tier.id,
      "user.created_at" => Time.current.iso8601,
      # The reapers remove the container once this has passed.
      "user.expires_at" => expires_at.utc.iso8601,

      # Security
      "security.nesting" => "false",
      "security.privileged" => "false",

      # Resource limits from instance tier
      **instance_tier.to_incus_limits
    }
    devices = nil

    if sandbox_type == "app_runtime"
      # The checkout boots with the environment its boot spec gives it, so
      # none of the platform's variables are set on its container. Its root
      # disk is the tier's, which holds a bundle and a database.
      devices = { "root" => { "type" => "disk", "path" => "/", "pool" => STORAGE_POOL, "size" => "#{instance_tier.disk_gb}GB" } }
    else
      config.merge!(
        "environment.RAILS_ENV" => "sandbox",
        "environment.SANDBOX_MODE" => "true",
        "environment.SANDBOX_SESSION_ID" => session_id,
        "environment.SANDBOX_TIMEOUT" => timeout.to_s,
        "environment.INSTANCE_TIER" => instance_tier.id
      )
    end

    {
      name: name,
      architecture: "x86_64",
      profiles: [ "default", "sandbox-restricted" ],
      source: {
        type: "image",
        alias: sandbox_image_for_type(sandbox_type, instance_tier)
      },
      config: config,
      devices: devices
    }.compact
  end

  def sandbox_image_for_type(sandbox_type, instance_tier)
    base_image = case sandbox_type
    when "playwright_mcp"
      "sandbox-playwright"
    when "terminal"
      "sandbox-terminal"
    when "research"
      "sandbox-research"
    when "app_runtime"
      APP_RUNTIME_IMAGE
    else
      "sandbox-base"
    end

    # Use GPU-enabled image if tier has GPU. The checkout image has no such
    # variant.
    if instance_tier.has_gpu? && sandbox_type != "app_runtime"
      "#{base_image}-gpu"
    else
      base_image
    end
  end

  def resolve_instance_tier(tier_param, sandbox_session)
    # If explicitly provided
    if tier_param.is_a?(SandboxInstanceTier)
      return tier_param
    elsif tier_param.is_a?(String) || tier_param.is_a?(Symbol)
      return SandboxInstanceTier.find(tier_param)
    end

    # Check if session has a tier preference
    if sandbox_session.respond_to?(:instance_tier) && sandbox_session.instance_tier.present?
      return SandboxInstanceTier.find(sandbox_session.instance_tier)
    end

    # Default based on sandbox type
    default_tier_for_sandbox_type(sandbox_session.sandbox_type)
  end

  def default_tier_for_sandbox_type(sandbox_type)
    case sandbox_type
    when "playwright_mcp"
      # Browser automation needs more resources
      SandboxInstanceTier.find(:cpu_medium)
    when "research"
      # Research may need more memory
      SandboxInstanceTier.find(:cpu_small)
    when "app_runtime"
      # A whole Rails app (bundle install, a database, the server) in 2 CPUs
      # and 8 GB, so one checkout's limit is half a 16 GB host rather than
      # all of it. See docs/infrastructure/app-runtime.md for sizing.
      SandboxInstanceTier.find(:cpu_small)
    else
      SandboxInstanceTier.find(:free)
    end
  end

  def wait_for_container_ready(container_name, timeout: 60, require_service: true)
    start_time = Time.current

    loop do
      state_response = api_request(:get, "/1.0/instances/#{container_name}/state")
      state = state_response["metadata"]

      if state["status"] == "Running"
        ip = extract_ip(state)
        if ip.present?
          # Check if the service is responding
          return ip if !require_service || service_ready?(ip)
        end
      end

      if state["status"] == "Error"
        raise ContainerError, "Container failed to start"
      end

      if Time.current - start_time > timeout
        raise ContainerError, "Timeout waiting for container to be ready"
      end

      sleep POLL_INTERVAL
    end
  end

  def extract_ip(state)
    # Try to get IPv4 address from eth0
    state.dig("network", "eth0", "addresses")&.find do |addr|
      addr["family"] == "inet" && addr["scope"] == "global"
    end&.dig("address")
  end

  def service_ready?(ip, port: 8080, path: "/up")
    response = Net::HTTP.get_response(URI("http://#{ip}:#{port}#{path}"))
    response.code == "200"
  rescue => e
    false
  end

  def api_request(method, path, body = nil)
    conn = build_connection
    params = (method == :get ? (body || {}).stringify_keys : {}).merge("project" => @project)

    response = case method
    when :get
      conn.get(path, params)
    when :post
      conn.post(path, body&.to_json) do |req|
        req.params = params
      end
    when :put
      conn.put(path, body&.to_json) do |req|
        req.params = params
      end
    when :delete
      conn.delete(path) do |req|
        req.params = params
      end
    end

    unless response.success?
      error_msg = response.body.is_a?(Hash) ? response.body["error"] : response.body
      raise Faraday::Error, "API request failed: #{error_msg}"
    end

    response.body
  end

  def build_connection
    if @host.start_with?("unix://")
      raise ConnectionError, "The Rails Incus adapter requires an HTTPS endpoint; set INCUS_HOST, INCUS_CERT_PATH and INCUS_KEY_PATH (Unix socket transport is not implemented)"
    end
    uri = URI.parse(@host)
    raise ConnectionError, "INCUS_HOST must be an HTTPS endpoint" unless uri.scheme == "https" && uri.host.present?
    raise ConnectionError, "Set both INCUS_CERT_PATH and INCUS_KEY_PATH" unless @cert_path.present? && @key_path.present?

    @connection ||= Faraday.new(url: api_url) do |f|
      f.options.open_timeout = 5
      f.options.timeout = 30
      f.request :json
      f.response :json
      f.response :raise_error

      f.ssl.client_cert = OpenSSL::X509::Certificate.new(File.read(@cert_path))
      f.ssl.client_key = OpenSSL::PKey.read(File.read(@key_path))
      f.ssl.ca_file = @server_ca_path if @server_ca_path.present?
      f.ssl.verify = true
      f.adapter Faraday.default_adapter
    end
  end

  def api_url
    if @host.start_with?("unix://")
      "http://localhost" # Placeholder for Unix socket
    else
      @host
    end
  end

  # Waits up to +timeout+ seconds for an operation to finish. Each request
  # long-polls: Incus answers when the operation finishes, or with it still
  # running after OPERATION_WAIT_SECONDS.
  def wait_for_operation(operation_url, timeout: 60)
    return unless operation_url

    operation_id = operation_url.split("/").last
    start_time = Time.current

    loop do
      wait = (timeout - (Time.current - start_time)).ceil.clamp(0, OPERATION_WAIT_SECONDS)
      response = api_request(:get, "/1.0/operations/#{operation_id}/wait", { "timeout" => wait })
      status = response.dig("metadata", "status")

      case status
      when "Success"
        return response["metadata"]
      when "Failure"
        error = response.dig("metadata", "err") || "Operation failed"
        raise ContainerError, error
      when "Cancelled"
        raise ContainerError, "Operation was cancelled"
      end

      if Time.current - start_time > timeout
        raise ContainerError, OPERATION_TIMED_OUT
      end

      sleep 0.5
    end
  end

  def sandbox_apparmor_profile
    # Restrictive AppArmor profile for sandboxes
    <<~APPARMOR
      # Deny access to sensitive paths
      deny /proc/sys/kernel/** w,
      deny /sys/kernel/** w,
      deny /proc/kcore r,

      # Allow network access (restricted by network policy)
      network inet stream,
      network inet dgram,
    APPARMOR
  end
end

# Stub for Faraday errors when not using full Faraday
unless defined?(Faraday::ResourceNotFound)
  module Faraday
    class ResourceNotFound < StandardError; end
    class Error < StandardError; end
  end
end
