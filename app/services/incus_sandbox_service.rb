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
class IncusSandboxService
  CONTAINER_PREFIX = "sandbox"
  DEFAULT_TIMEOUT = 900 # 15 minutes
  POLL_INTERVAL = 1 # seconds

  class ContainerError < StandardError; end
  class ContainerNotFoundError < StandardError; end
  class ConnectionError < StandardError; end

  def initialize(config = {})
    @host = config[:host] || ENV.fetch("INCUS_HOST", "unix:///var/lib/incus/unix.socket")
    @cert_path = config[:cert_path] || ENV["INCUS_CERT_PATH"]
    @key_path = config[:key_path] || ENV["INCUS_KEY_PATH"]
    @project = config[:project] || ENV.fetch("INCUS_PROJECT", "agent-sandboxes")
  end

  # Create a new sandbox container for the given session
  #
  # @param sandbox_session [SandboxSession] The session to create a container for
  # @return [Hash] Container details including name and IP
  def create_sandbox(sandbox_session)
    container_name = generate_container_name(sandbox_session.session_id)

    config = build_container_config(
      name: container_name,
      session_id: sandbox_session.session_id,
      owner_id: sandbox_session.owner_id,
      sandbox_type: sandbox_session.sandbox_type,
      timeout: sandbox_session.timeout_seconds || DEFAULT_TIMEOUT
    )

    begin
      # Create the container
      response = api_request(:post, "/1.0/instances", config)
      wait_for_operation(response["operation"]) if response["operation"]

      # Start the container
      start_response = api_request(:put, "/1.0/instances/#{container_name}/state", {
        action: "start",
        timeout: 30
      })
      wait_for_operation(start_response["operation"]) if start_response["operation"]

      # Wait for network and readiness
      container_ip = wait_for_container_ready(container_name)

      {
        container_name: container_name,
        container_ip: container_ip,
        url: "http://#{container_ip}:8080",
        project: @project,
        created_at: Time.current
      }
    rescue => e
      # Cleanup on failure
      terminate(container_name) rescue nil
      Rails.logger.error("Failed to create sandbox container: #{e.message}")
      raise ContainerError, "Failed to create sandbox: #{e.message}"
    end
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

  # List all sandbox containers
  #
  # @return [Array<Hash>] List of container statuses
  def list_sandboxes
    response = api_request(:get, "/1.0/instances", { "recursion" => 1 })
    instances = response["metadata"] || []

    instances.select { |i| i["name"].start_with?(CONTAINER_PREFIX) }.map do |instance|
      {
        name: instance["name"],
        status: instance["status"],
        created_at: instance["created_at"],
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

    wait_for_operation(response["operation"])
  end

  # Get logs from a sandbox container
  #
  # @param container_name [String] The container name
  # @param log_file [String] Log file to read (default: /var/log/sandbox.log)
  # @return [String] Log contents
  def container_logs(container_name, log_file: "/var/log/sandbox.log")
    result = exec_in_container(container_name, ["cat", log_file])
    result.dig("metadata", "output", "1") || ""
  rescue => e
    Rails.logger.warn("Failed to get logs for #{container_name}: #{e.message}")
    ""
  end

  # Cleanup expired sandbox containers
  #
  # @return [Integer] Number of containers cleaned up
  def cleanup_expired
    sandboxes = list_sandboxes
    cleaned = 0

    sandboxes.each do |sandbox|
      created_at = Time.parse(sandbox[:created_at])
      if Time.current - created_at > DEFAULT_TIMEOUT
        terminate(sandbox[:name])
        cleaned += 1
        Rails.logger.info("Cleaned up expired sandbox: #{sandbox[:name]}")
      end
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

  private

  def generate_container_name(session_id)
    "#{CONTAINER_PREFIX}-#{session_id[0..7]}-#{SecureRandom.hex(4)}"
  end

  def build_container_config(name:, session_id:, owner_id:, sandbox_type:, timeout:)
    {
      name: name,
      architecture: "x86_64",
      profiles: ["default", "sandbox-restricted"],
      source: {
        type: "image",
        alias: sandbox_image_for_type(sandbox_type)
      },
      config: {
        # Metadata
        "user.session_id" => session_id,
        "user.owner_id" => owner_id.to_s,
        "user.sandbox_type" => sandbox_type,
        "user.created_at" => Time.current.iso8601,

        # Security
        "security.nesting" => "false",
        "security.privileged" => "false",

        # Resource limits based on sandbox type
        **resource_limits_for_type(sandbox_type),

        # Environment variables
        "environment.RAILS_ENV" => "sandbox",
        "environment.SANDBOX_MODE" => "true",
        "environment.SANDBOX_SESSION_ID" => session_id,
        "environment.SANDBOX_TIMEOUT" => timeout.to_s
      }
    }
  end

  def sandbox_image_for_type(sandbox_type)
    case sandbox_type
    when "playwright_mcp"
      "sandbox-playwright"
    when "terminal"
      "sandbox-terminal"
    when "research"
      "sandbox-research"
    else
      "sandbox-base"
    end
  end

  def resource_limits_for_type(sandbox_type)
    case sandbox_type
    when "playwright_mcp"
      {
        "limits.cpu" => "4",
        "limits.memory" => "4GB",
        "limits.processes" => "1000"
      }
    when "terminal"
      {
        "limits.cpu" => "1",
        "limits.memory" => "1GB",
        "limits.processes" => "200"
      }
    when "research"
      {
        "limits.cpu" => "2",
        "limits.memory" => "2GB",
        "limits.processes" => "500"
      }
    else
      {
        "limits.cpu" => "2",
        "limits.memory" => "2GB",
        "limits.processes" => "500"
      }
    end
  end

  def wait_for_container_ready(container_name, timeout: 60)
    start_time = Time.current

    loop do
      state_response = api_request(:get, "/1.0/instances/#{container_name}/state")
      state = state_response["metadata"]

      if state["status"] == "Running"
        ip = extract_ip(state)
        if ip.present?
          # Check if the service is responding
          if service_ready?(ip)
            return ip
          end
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
    params = { project: @project }

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
    @connection ||= Faraday.new(url: api_url) do |f|
      f.request :json
      f.response :json
      f.response :raise_error

      if @host.start_with?("unix://")
        # Unix socket connection
        f.adapter :net_http do |http|
          http.socket_class = UnixSocket
        end
      else
        # HTTPS connection with client certs
        if @cert_path && @key_path
          f.ssl.client_cert = OpenSSL::X509::Certificate.new(File.read(@cert_path))
          f.ssl.client_key = OpenSSL::PKey::RSA.new(File.read(@key_path))
          f.ssl.verify = true
        end
        f.adapter Faraday.default_adapter
      end
    end
  end

  def api_url
    if @host.start_with?("unix://")
      "http://localhost" # Placeholder for Unix socket
    else
      @host
    end
  end

  def wait_for_operation(operation_url, timeout: 60)
    return unless operation_url

    operation_id = operation_url.split("/").last
    start_time = Time.current

    loop do
      response = api_request(:get, "/1.0/operations/#{operation_id}")
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
        raise ContainerError, "Operation timed out"
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
