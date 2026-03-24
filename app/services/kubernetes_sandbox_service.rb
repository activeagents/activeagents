# frozen_string_literal: true

# KubernetesSandboxService
#
# Manages ephemeral Kubernetes pods for agent sandbox sessions.
# Each user session gets an isolated pod with gVisor runtime for security.
#
# Usage:
#   service = KubernetesSandboxService.new
#   pod = service.create_sandbox_pod(sandbox_session)
#   status = service.pod_status(pod_name)
#   service.terminate_pod(pod_name)
#
class KubernetesSandboxService
  NAMESPACE = "agent-sandboxes"
  POD_TIMEOUT = 900 # 15 minutes
  POLL_INTERVAL = 2 # seconds

  class PodCreationError < StandardError; end
  class PodNotFoundError < StandardError; end
  class KubernetesError < StandardError; end

  def initialize
    @client = build_kubernetes_client
  end

  # Create a new sandbox pod for the given session
  #
  # @param sandbox_session [SandboxSession] The session to create a pod for
  # @return [Hash] Pod details including name and IP
  def create_sandbox_pod(sandbox_session)
    pod_name = "sandbox-#{sandbox_session.session_id[0..7]}-#{SecureRandom.hex(4)}"

    pod_manifest = build_pod_manifest(
      name: pod_name,
      session_id: sandbox_session.session_id,
      owner_id: sandbox_session.owner_id,
      sandbox_type: sandbox_session.sandbox_type,
      max_runs: sandbox_session.max_runs,
      timeout: sandbox_session.timeout_seconds
    )

    begin
      @client.create_pod(pod_manifest)

      # Wait for pod to be ready
      pod_ip = wait_for_pod_ready(pod_name)

      {
        pod_name: pod_name,
        pod_ip: pod_ip,
        namespace: NAMESPACE,
        url: "http://#{pod_ip}:8080",
        created_at: Time.current
      }
    rescue => e
      Rails.logger.error("Failed to create sandbox pod: #{e.message}")
      raise PodCreationError, "Failed to create sandbox pod: #{e.message}"
    end
  end

  # Get the status of a sandbox pod
  #
  # @param pod_name [String] The pod name
  # @return [Hash] Pod status details
  def pod_status(pod_name)
    pod = @client.get_pod(pod_name, NAMESPACE)

    {
      name: pod.metadata.name,
      phase: pod.status.phase,
      ip: pod.status.podIP,
      ready: pod_ready?(pod),
      start_time: pod.status.startTime,
      conditions: pod.status.conditions&.map { |c| { type: c.type, status: c.status } }
    }
  rescue Kubeclient::ResourceNotFoundError
    raise PodNotFoundError, "Pod #{pod_name} not found"
  end

  # Terminate a sandbox pod
  #
  # @param pod_name [String] The pod name to terminate
  # @return [Boolean] true if deleted
  def terminate_pod(pod_name)
    @client.delete_pod(pod_name, NAMESPACE)
    true
  rescue Kubeclient::ResourceNotFoundError
    # Already deleted
    true
  rescue => e
    Rails.logger.error("Failed to terminate pod #{pod_name}: #{e.message}")
    false
  end

  # List all sandbox pods
  #
  # @param label_selector [String] Optional label selector
  # @return [Array<Hash>] List of pod statuses
  def list_sandbox_pods(label_selector: "app.kubernetes.io/component=sandbox")
    pods = @client.get_pods(
      namespace: NAMESPACE,
      label_selector: label_selector
    )

    pods.map do |pod|
      {
        name: pod.metadata.name,
        phase: pod.status.phase,
        ip: pod.status.podIP,
        session_id: pod.metadata.labels["sandbox-session-id"],
        created_at: pod.metadata.creationTimestamp,
        ready: pod_ready?(pod)
      }
    end
  end

  # Get logs from a sandbox pod
  #
  # @param pod_name [String] The pod name
  # @param tail_lines [Integer] Number of lines to return
  # @return [String] Pod logs
  def pod_logs(pod_name, tail_lines: 100)
    @client.get_pod_log(
      pod_name,
      NAMESPACE,
      tail_lines: tail_lines,
      timestamps: true
    )
  rescue Kubeclient::ResourceNotFoundError
    raise PodNotFoundError, "Pod #{pod_name} not found"
  end

  # Execute a command in a sandbox pod
  #
  # @param pod_name [String] The pod name
  # @param command [Array<String>] Command to execute
  # @return [Hash] stdout, stderr, exit_code
  def exec_in_pod(pod_name, command)
    # Note: This requires websocket support in kubeclient
    # For production, consider using the Kubernetes exec API directly
    raise NotImplementedError, "Use the pod's HTTP API instead"
  end

  # Cleanup expired sandbox pods
  #
  # @return [Integer] Number of pods cleaned up
  def cleanup_expired_pods
    pods = list_sandbox_pods
    cleaned = 0

    pods.each do |pod|
      # Check if pod has exceeded timeout
      created_at = Time.parse(pod[:created_at])
      if Time.current - created_at > POD_TIMEOUT
        terminate_pod(pod[:name])
        cleaned += 1
        Rails.logger.info("Cleaned up expired sandbox pod: #{pod[:name]}")
      end
    end

    cleaned
  end

  private

  def build_kubernetes_client
    if Rails.env.development? || Rails.env.test?
      # Use mock client in development
      MockKubernetesClient.new
    else
      # Production: Use in-cluster config or kubeconfig
      config = if File.exist?("/var/run/secrets/kubernetes.io/serviceaccount/token")
        # Running inside Kubernetes
        Kubeclient::Config.new(
          Kubeclient::Config::Context.new(
            "https://kubernetes.default.svc",
            "v1",
            ssl_options: {
              ca_file: "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
            },
            auth_options: {
              bearer_token_file: "/var/run/secrets/kubernetes.io/serviceaccount/token"
            }
          )
        )
      else
        # Running outside cluster - use kubeconfig
        Kubeclient::Config.read(
          ENV.fetch("KUBECONFIG", File.expand_path("~/.kube/config"))
        )
      end

      Kubeclient::Client.new(
        config.context.api_endpoint,
        "v1",
        ssl_options: config.context.ssl_options,
        auth_options: config.context.auth_options
      )
    end
  end

  def build_pod_manifest(name:, session_id:, owner_id:, sandbox_type:, max_runs:, timeout:)
    {
      apiVersion: "v1",
      kind: "Pod",
      metadata: {
        name: name,
        namespace: NAMESPACE,
        labels: {
          "app.kubernetes.io/name" => "agent-sandbox",
          "app.kubernetes.io/component" => "sandbox",
          "sandbox-session-id" => session_id,
          "sandbox-type" => sandbox_type
        },
        annotations: {
          "sandbox.gke.io/runtime" => "gvisor"
        }
      },
      spec: {
        serviceAccountName: "sandbox-runner",
        activeDeadlineSeconds: timeout,
        restartPolicy: "Never",

        securityContext: {
          runAsNonRoot: true,
          runAsUser: 1000,
          runAsGroup: 1000,
          fsGroup: 1000,
          seccompProfile: { type: "RuntimeDefault" }
        },

        containers: [
          {
            name: "sandbox",
            image: sandbox_image_for_type(sandbox_type),
            imagePullPolicy: "Always",

            resources: resource_limits_for_type(sandbox_type),

            env: [
              { name: "RAILS_ENV", value: "sandbox" },
              { name: "SANDBOX_MODE", value: "true" },
              { name: "SANDBOX_SESSION_ID", value: session_id },
              { name: "SANDBOX_OWNER_ID", value: owner_id.to_s },
              { name: "SANDBOX_MAX_RUNS", value: max_runs.to_s },
              { name: "SANDBOX_TIMEOUT", value: timeout.to_s },
              { name: "PLAYWRIGHT_BROWSERS_PATH", value: "/usr/bin" },
              # API keys from secrets
              {
                name: "ANTHROPIC_API_KEY",
                valueFrom: {
                  secretKeyRef: { name: "sandbox-secrets", key: "anthropic-api-key" }
                }
              },
              {
                name: "OPENAI_API_KEY",
                valueFrom: {
                  secretKeyRef: { name: "sandbox-secrets", key: "openai-api-key" }
                }
              }
            ],

            securityContext: {
              allowPrivilegeEscalation: false,
              readOnlyRootFilesystem: false,
              capabilities: { drop: [ "ALL" ] }
            },

            readinessProbe: {
              httpGet: { path: "/up", port: 8080 },
              initialDelaySeconds: 5,
              periodSeconds: 5,
              timeoutSeconds: 3
            },

            livenessProbe: {
              httpGet: { path: "/up", port: 8080 },
              initialDelaySeconds: 30,
              periodSeconds: 10,
              timeoutSeconds: 5
            },

            ports: [
              { containerPort: 8080, protocol: "TCP" }
            ]
          }
        ],

        # Tolerations for gVisor nodes
        tolerations: [
          {
            key: "sandbox.gke.io/runtime",
            operator: "Equal",
            value: "gvisor",
            effect: "NoSchedule"
          }
        ]
      }
    }
  end

  def sandbox_image_for_type(sandbox_type)
    base_image = ENV.fetch("SANDBOX_IMAGE", "gcr.io/#{ENV['GOOGLE_CLOUD_PROJECT']}/sandbox:latest")

    case sandbox_type
    when "playwright_mcp"
      base_image.gsub(":latest", ":playwright")
    when "terminal"
      base_image.gsub(":latest", ":terminal")
    when "research"
      base_image.gsub(":latest", ":research")
    else
      base_image
    end
  end

  def resource_limits_for_type(sandbox_type)
    case sandbox_type
    when "playwright_mcp"
      # Browser automation needs more resources
      {
        requests: { cpu: "1", memory: "1Gi" },
        limits: { cpu: "4", memory: "4Gi" }
      }
    when "terminal"
      # Terminal sessions are lightweight
      {
        requests: { cpu: "250m", memory: "256Mi" },
        limits: { cpu: "1", memory: "1Gi" }
      }
    when "research"
      # Research needs moderate resources
      {
        requests: { cpu: "500m", memory: "512Mi" },
        limits: { cpu: "2", memory: "2Gi" }
      }
    else
      {
        requests: { cpu: "500m", memory: "512Mi" },
        limits: { cpu: "2", memory: "2Gi" }
      }
    end
  end

  def wait_for_pod_ready(pod_name, timeout: 60)
    start_time = Time.current

    loop do
      pod = @client.get_pod(pod_name, NAMESPACE)

      if pod_ready?(pod) && pod.status.podIP.present?
        return pod.status.podIP
      end

      if pod.status.phase == "Failed"
        raise PodCreationError, "Pod failed to start: #{pod.status.message}"
      end

      if Time.current - start_time > timeout
        raise PodCreationError, "Timeout waiting for pod to be ready"
      end

      sleep POLL_INTERVAL
    end
  end

  def pod_ready?(pod)
    pod.status.conditions&.any? do |condition|
      condition.type == "Ready" && condition.status == "True"
    end
  end

  # Mock client for development/test
  class MockKubernetesClient
    def initialize
      @pods = {}
    end

    def create_pod(manifest)
      name = manifest[:metadata][:name]
      @pods[name] = OpenStruct.new(
        metadata: OpenStruct.new(
          name: name,
          namespace: manifest[:metadata][:namespace],
          labels: manifest[:metadata][:labels],
          creationTimestamp: Time.current.iso8601
        ),
        status: OpenStruct.new(
          phase: "Running",
          podIP: "10.0.0.#{rand(1..254)}",
          startTime: Time.current.iso8601,
          conditions: [
            OpenStruct.new(type: "Ready", status: "True")
          ]
        ),
        spec: manifest[:spec]
      )
    end

    def get_pod(name, namespace)
      @pods[name] || raise(Kubeclient::ResourceNotFoundError.new(404, "Not Found", {}))
    end

    def delete_pod(name, namespace)
      @pods.delete(name)
      true
    end

    def get_pods(namespace:, label_selector:)
      @pods.values
    end

    def get_pod_log(name, namespace, **options)
      "Mock log output for pod #{name}"
    end
  end
end

# Stub for Kubeclient error when not installed
unless defined?(Kubeclient)
  module Kubeclient
    class ResourceNotFoundError < StandardError
      def initialize(code, message, response)
        super(message)
      end
    end
  end
end
