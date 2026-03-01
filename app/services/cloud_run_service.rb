# frozen_string_literal: true

# CloudRunService handles interaction with Google Cloud Run API
# for managing sandbox container instances.
class CloudRunService
  class << self
    # Create a new Cloud Run job for a sandbox session
    def create_sandbox_job(sandbox_session)
      job_id = "sandbox-#{sandbox_session.session_id}"

      job_config = {
        template: {
          template: {
            containers: [{
              image: sandbox_image,
              env: sandbox_env_vars(sandbox_session),
              resources: {
                limits: {
                  cpu: "1",
                  memory: "512Mi"
                }
              }
            }],
            maxRetries: 0,
            timeout: "#{sandbox_session.timeout_seconds}s"
          }
        }
      }

      response = cloud_run_client.create_job(
        parent: "projects/#{project_id}/locations/#{region}",
        job: job_config,
        job_id: job_id
      )

      # Execute the job immediately
      execution = cloud_run_client.run_job(name: response.name)

      {
        job_id: job_id,
        job_name: response.name,
        execution_name: execution.name,
        url: execution.uri
      }
    end

    # Get status of a Cloud Run job
    def job_status(job_id)
      return mock_job_status(job_id) if Rails.env.development? || Rails.env.test?

      job = cloud_run_client.get_job(name: job_name(job_id))

      {
        status: map_job_status(job.latest_created_execution&.completion_time),
        conditions: job.conditions&.map { |c| { type: c.type, status: c.status } },
        execution_count: job.execution_count,
        created_at: job.create_time&.to_time&.iso8601,
        updated_at: job.update_time&.to_time&.iso8601
      }
    rescue Google::Cloud::NotFoundError
      { status: "not_found" }
    end

    # Get detailed information about a Cloud Run job
    def job_details(job_id)
      return mock_job_details(job_id) if Rails.env.development? || Rails.env.test?

      job = cloud_run_client.get_job(name: job_name(job_id))
      execution = job.latest_created_execution

      {
        job_id: job_id,
        status: map_job_status(execution&.completion_time),
        image: job.template&.template&.containers&.first&.image,
        cpu: job.template&.template&.containers&.first&.resources&.limits&.dig("cpu"),
        memory: job.template&.template&.containers&.first&.resources&.limits&.dig("memory"),
        timeout: job.template&.template&.timeout,
        execution: execution ? {
          name: execution.name,
          status: execution.reconciling ? "running" : "completed",
          started_at: execution.start_time&.to_time&.iso8601,
          completed_at: execution.completion_time&.to_time&.iso8601
        } : nil
      }
    rescue Google::Cloud::NotFoundError
      nil
    end

    # Fetch logs from Cloud Logging for a Cloud Run job
    def job_logs(job_id, limit: 100, severity: nil)
      return mock_logs(job_id) if Rails.env.development? || Rails.env.test?

      filter = "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"sandbox-#{job_id}\""
      filter += " AND severity>=#{severity.upcase}" if severity.present?

      entries = logging_client.list_log_entries(
        resource_names: ["projects/#{project_id}"],
        filter: filter,
        order_by: "timestamp desc",
        page_size: limit
      )

      entries.map do |entry|
        {
          timestamp: entry.timestamp&.to_time&.iso8601,
          severity: entry.severity.to_s,
          message: entry.payload.is_a?(String) ? entry.payload : entry.payload.to_json,
          labels: entry.labels&.to_h
        }
      end
    rescue StandardError => e
      Rails.logger.error "[CloudRunService] Failed to fetch logs: #{e.message}"
      []
    end

    # Terminate a running Cloud Run job
    def terminate_job(job_id, reason: nil)
      return mock_terminate(job_id) if Rails.env.development? || Rails.env.test?

      # Delete the job to stop all executions
      cloud_run_client.delete_job(name: job_name(job_id))

      Rails.logger.info "[CloudRunService] Terminated job #{job_id}: #{reason}"
      true
    rescue Google::Cloud::NotFoundError
      Rails.logger.warn "[CloudRunService] Job #{job_id} not found for termination"
      false
    end

    # List all sandbox jobs
    def list_sandbox_jobs(status: nil)
      return mock_list_jobs if Rails.env.development? || Rails.env.test?

      jobs = cloud_run_client.list_jobs(
        parent: "projects/#{project_id}/locations/#{region}"
      ).select { |j| j.name.include?("sandbox-") }

      jobs.map do |job|
        {
          job_id: job.name.split("/").last,
          status: map_job_status(job.latest_created_execution&.completion_time),
          created_at: job.create_time&.to_time&.iso8601
        }
      end
    end

    private

    def cloud_run_client
      @cloud_run_client ||= Google::Cloud::Run::V2::Jobs::Client.new
    end

    def logging_client
      @logging_client ||= Google::Cloud::Logging.new(project_id: project_id)
    end

    def project_id
      ENV.fetch("GOOGLE_CLOUD_PROJECT", "activeagents-prod")
    end

    def region
      ENV.fetch("CLOUD_RUN_REGION", "us-central1")
    end

    def sandbox_image
      ENV.fetch("SANDBOX_IMAGE", "gcr.io/#{project_id}/activeagents:sandbox")
    end

    def job_name(job_id)
      "projects/#{project_id}/locations/#{region}/jobs/sandbox-#{job_id}"
    end

    def sandbox_env_vars(session)
      [
        { name: "RAILS_ENV", value: "sandbox" },
        { name: "SANDBOX_MODE", value: "true" },
        { name: "SANDBOX_SESSION_ID", value: session.session_id },
        { name: "SANDBOX_OWNER_ID", value: session.user_id&.to_s },
        { name: "SANDBOX_MAX_RUNS", value: session.max_runs.to_s },
        { name: "SANDBOX_TIMEOUT", value: session.timeout_seconds.to_s },
        { name: "ANTHROPIC_API_KEY", value: ENV.fetch("ANTHROPIC_API_KEY", "") }
      ]
    end

    def map_job_status(completion_time)
      return "running" if completion_time.nil?
      "completed"
    end

    # Mock methods for development/test
    def mock_job_status(job_id)
      {
        status: "running",
        conditions: [{ type: "Ready", status: "True" }],
        execution_count: 1,
        created_at: Time.current.iso8601,
        updated_at: Time.current.iso8601
      }
    end

    def mock_job_details(job_id)
      {
        job_id: job_id,
        status: "running",
        image: "gcr.io/activeagents-prod/activeagents:sandbox",
        cpu: "1",
        memory: "512Mi",
        timeout: "300s",
        execution: {
          name: "sandbox-#{job_id}-exec-1",
          status: "running",
          started_at: 5.minutes.ago.iso8601,
          completed_at: nil
        }
      }
    end

    def mock_logs(job_id)
      [
        { timestamp: 1.minute.ago.iso8601, severity: "INFO", message: "Container started", labels: {} },
        { timestamp: 30.seconds.ago.iso8601, severity: "INFO", message: "Sandbox ready", labels: {} }
      ]
    end

    def mock_terminate(job_id)
      Rails.logger.info "[CloudRunService] Mock terminate job #{job_id}"
      true
    end

    def mock_list_jobs
      [
        { job_id: "test-session-1", status: "running", created_at: 10.minutes.ago.iso8601 },
        { job_id: "test-session-2", status: "completed", created_at: 1.hour.ago.iso8601 }
      ]
    end
  end
end
