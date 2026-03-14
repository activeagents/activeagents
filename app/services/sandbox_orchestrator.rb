# frozen_string_literal: true

# SandboxOrchestrator
#
# Unified interface for managing agent sandbox sessions.
# Supports multiple backends for cloud-agnostic deployment:
#
#   - incus:     Self-hosted Incus containers (any Linux host)
#   - cloud_run: Google Cloud Run Jobs (serverless)
#   - kubernetes: Kubernetes pods (GKE, EKS, self-hosted k8s)
#
# Configuration:
#   Set SANDBOX_BACKEND environment variable to choose backend.
#   Default: "incus" for simplicity
#
# Usage:
#   orchestrator = SandboxOrchestrator.new
#   result = orchestrator.create_sandbox(session)
#   status = orchestrator.status(container_id)
#   orchestrator.terminate(container_id)
#
class SandboxOrchestrator
  BACKENDS = %w[incus cloud_run kubernetes mock].freeze

  class UnsupportedBackendError < StandardError; end

  def initialize(backend: nil)
    @backend_name = backend || ENV.fetch("SANDBOX_BACKEND", "incus")
    raise UnsupportedBackendError, "Unknown backend: #{@backend_name}" unless BACKENDS.include?(@backend_name)

    @backend = build_backend
  end

  attr_reader :backend_name

  # Create a new sandbox for the given session
  #
  # @param sandbox_session [SandboxSession] The session to create a sandbox for
  # @param instance_tier [String, Symbol, SandboxInstanceTier] Optional instance tier
  # @return [Hash] Sandbox details including ID/name and URL
  def create_sandbox(sandbox_session, instance_tier: nil)
    # Resolve tier
    tier = resolve_tier(instance_tier)

    result = case @backend_name
    when "incus"
      @backend.create_sandbox(sandbox_session, instance_tier: tier)
    when "kubernetes"
      @backend.create_sandbox_pod(sandbox_session) # TODO: add tier support
    when "cloud_run"
      @backend.create_sandbox_job(sandbox_session) # TODO: add tier support
    when "mock"
      @backend.create_sandbox(sandbox_session, instance_tier: tier)
    end

    # Normalize response format across backends
    {
      sandbox_id: result[:container_name] || result[:pod_name] || result[:job_name],
      url: result[:url],
      ip: result[:container_ip] || result[:pod_ip],
      backend: @backend_name,
      instance_tier: result[:instance_tier] || tier&.id,
      resources: result[:resources],
      hourly_cost: result[:hourly_cost] || tier&.hourly_cost&.to_f,
      created_at: result[:created_at] || Time.current
    }
  end

  # List available instance tiers
  #
  # @param category [String, nil] Optional category filter (free, pro, enterprise)
  # @return [Array<SandboxInstanceTier>] Available tiers
  def available_tiers(category: nil)
    tiers = SandboxInstanceTier.available
    tiers = tiers.select { |t| t.category == category.to_s } if category
    tiers
  end

  # Get a specific instance tier
  #
  # @param tier_id [String, Symbol] Tier ID
  # @return [SandboxInstanceTier]
  def get_tier(tier_id)
    SandboxInstanceTier.find(tier_id)
  end

  # Get the status of a sandbox
  #
  # @param sandbox_id [String] The sandbox ID (container name, pod name, etc.)
  # @return [Hash] Sandbox status
  def status(sandbox_id)
    case @backend_name
    when "incus"
      @backend.container_status(sandbox_id)
    when "kubernetes"
      @backend.pod_status(sandbox_id)
    when "cloud_run"
      @backend.job_status(sandbox_id)
    when "mock"
      @backend.status(sandbox_id)
    end
  end

  # Terminate a sandbox
  #
  # @param sandbox_id [String] The sandbox ID to terminate
  # @return [Boolean] true if terminated
  def terminate(sandbox_id)
    case @backend_name
    when "incus"
      @backend.terminate(sandbox_id)
    when "kubernetes"
      @backend.terminate_pod(sandbox_id)
    when "cloud_run"
      @backend.cancel_job(sandbox_id)
    when "mock"
      @backend.terminate(sandbox_id)
    end
  end

  # List all active sandboxes
  #
  # @return [Array<Hash>] List of sandbox statuses
  def list_sandboxes
    case @backend_name
    when "incus"
      @backend.list_sandboxes
    when "kubernetes"
      @backend.list_sandbox_pods
    when "cloud_run"
      @backend.list_jobs
    when "mock"
      @backend.list_sandboxes
    end
  end

  # Cleanup expired sandboxes
  #
  # @return [Integer] Number of sandboxes cleaned up
  def cleanup_expired
    case @backend_name
    when "incus"
      @backend.cleanup_expired
    when "kubernetes"
      @backend.cleanup_expired_pods
    when "cloud_run"
      @backend.cleanup_expired_jobs
    when "mock"
      @backend.cleanup_expired
    end
  end

  # Check if the backend is healthy
  #
  # @return [Boolean] true if backend is reachable
  def healthy?
    case @backend_name
    when "incus"
      @backend.list_sandboxes
      true
    when "kubernetes"
      @backend.list_sandbox_pods
      true
    when "cloud_run"
      true # Cloud Run is always available
    when "mock"
      true
    end
  rescue => e
    Rails.logger.error("Sandbox backend health check failed: #{e.message}")
    false
  end

  # Get backend-specific configuration info
  #
  # @return [Hash] Backend configuration
  def backend_info
    {
      name: @backend_name,
      class: @backend.class.name,
      healthy: healthy?,
      features: backend_features
    }
  end

  private

  def build_backend
    case @backend_name
    when "incus"
      IncusSandboxService.new
    when "kubernetes"
      KubernetesSandboxService.new
    when "cloud_run"
      CloudRunService.new
    when "mock"
      MockSandboxBackend.new
    end
  end

  def resolve_tier(tier_param)
    return nil unless tier_param

    if tier_param.is_a?(SandboxInstanceTier)
      tier_param
    else
      SandboxInstanceTier.find(tier_param)
    end
  rescue ArgumentError
    Rails.logger.warn("Unknown instance tier: #{tier_param}, using default")
    SandboxInstanceTier.default_tier
  end

  def backend_features
    case @backend_name
    when "incus"
      {
        cloud_agnostic: true,
        isolation: "namespaces + apparmor",
        networking: "bridge",
        persistent_storage: true,
        live_migration: true,
        self_hosted: true
      }
    when "kubernetes"
      {
        cloud_agnostic: true,
        isolation: "pods + gvisor",
        networking: "cni + network_policies",
        persistent_storage: true,
        live_migration: false,
        self_hosted: true
      }
    when "cloud_run"
      {
        cloud_agnostic: false,
        isolation: "gvisor",
        networking: "vpc_connector",
        persistent_storage: false,
        live_migration: false,
        self_hosted: false
      }
    when "mock"
      {
        cloud_agnostic: true,
        isolation: "none",
        networking: "mock",
        persistent_storage: false,
        live_migration: false,
        self_hosted: true
      }
    end
  end

  # Mock backend for development and testing
  class MockSandboxBackend
    def initialize
      @sandboxes = {}
    end

    def create_sandbox(session, instance_tier: nil)
      tier = instance_tier || SandboxInstanceTier.free_tier
      name = "mock-sandbox-#{SecureRandom.hex(4)}"

      @sandboxes[name] = {
        container_name: name,
        container_ip: "127.0.0.1",
        url: "http://127.0.0.1:8080",
        session_id: session.session_id,
        status: "running",
        instance_tier: tier.id,
        resources: {
          cpu_cores: tier.cpu_cores,
          memory_gb: tier.memory_gb,
          gpu: tier.gpu
        },
        hourly_cost: tier.hourly_cost.to_f,
        created_at: Time.current
      }
      @sandboxes[name]
    end

    def status(sandbox_id)
      @sandboxes[sandbox_id] || { status: "not_found" }
    end

    def terminate(sandbox_id)
      @sandboxes.delete(sandbox_id)
      true
    end

    def list_sandboxes
      @sandboxes.values
    end

    def cleanup_expired
      0
    end
  end
end
