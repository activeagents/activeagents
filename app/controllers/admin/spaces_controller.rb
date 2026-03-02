# frozen_string_literal: true

module Admin
  class SpacesController < BaseController
    before_action :set_space, only: [ :show, :terminate, :logs ]

    # GET /admin/spaces
    # List all sandbox spaces with their status
    def index
      @spaces = SandboxSession.includes(:user, :agent_template)
                              .order(created_at: :desc)
                              .limit(50)

      # Fetch Cloud Run status for active spaces
      @cloud_run_status = fetch_cloud_run_status(@spaces.select(&:active?))

      render inertia: "Admin/Spaces/Index", props: {
        spaces: @spaces.map { |s| space_props(s, @cloud_run_status[s.cloud_run_job_id]) },
        pagination: { current_page: 1, total_pages: 1, total_count: @spaces.size },
        stats: space_stats
      }
    end

    # GET /admin/spaces/:id
    # Show detailed space information including Cloud Run metrics
    def show
      cloud_run_info = fetch_cloud_run_details(@space)

      render inertia: "Admin/Spaces/Show", props: {
        space: space_details(@space),
        cloud_run: cloud_run_info,
        runs: @space.runs,
        logs: recent_logs(@space)
      }
    end

    # POST /admin/spaces/:id/terminate
    # Force terminate a sandbox space
    def terminate
      reason = params[:reason] || "Terminated by admin"

      @space.expire!

      # Force terminate Cloud Run job if running
      if @space.cloud_run_job_id.present?
        terminate_cloud_run_job(@space.cloud_run_job_id, reason)
      end

      redirect_to admin_spaces_path, notice: "Space #{@space.session_id} terminated"
    end

    # GET /admin/spaces/:id/logs
    # Fetch recent logs from Cloud Run
    def logs
      logs = fetch_cloud_run_logs(@space)

      render json: { logs: logs }
    end

    private

    def set_space
      @space = SandboxSession.find(params[:id])
    end

    def space_props(space, cloud_run_status = nil)
      {
        id: space.id,
        session_id: space.session_id,
        sandbox_type: space.sandbox_type,
        status: space.status,
        user: space.user ? { id: space.user.id, email: space.user.email_address } : nil,
        template: space.agent_template&.name,
        runs_count: space.runs_count,
        max_runs: space.max_runs,
        total_tokens: space.total_tokens,
        expires_at: space.expires_at&.iso8601,
        created_at: space.created_at.iso8601,
        cloud_run_status: cloud_run_status,
        cloud_run_url: space.cloud_run_url
      }
    end

    def space_details(space)
      space_props(space).merge(
        total_duration_ms: space.total_duration_ms,
        last_activity_at: space.last_activity_at&.iso8601,
        cloud_run_job_id: space.cloud_run_job_id
      )
    end

    def space_stats
      {
        total: SandboxSession.count,
        active: SandboxSession.active.count,
        expired: SandboxSession.where(status: :expired).count,
        anonymous: SandboxSession.anonymous.count,
        by_type: SandboxSession.group(:sandbox_type).count,
        runs_today: SandboxSession.where("created_at > ?", Time.current.beginning_of_day)
                                   .sum(:runs_count)
      }
    end

    def pagination_props(collection)
      {
        current_page: collection.current_page,
        total_pages: collection.total_pages,
        total_count: collection.total_count
      }
    end

    def fetch_cloud_run_status(spaces)
      return {} if spaces.empty?

      # Use Cloud Run Admin API to get job status
      status = {}

      spaces.each do |space|
        next unless space.cloud_run_job_id.present?

        begin
          status[space.cloud_run_job_id] = CloudRunService.job_status(space.cloud_run_job_id)
        rescue StandardError => e
          Rails.logger.warn "[Admin] Failed to fetch Cloud Run status for #{space.cloud_run_job_id}: #{e.message}"
          status[space.cloud_run_job_id] = { status: "unknown", error: e.message }
        end
      end

      status
    end

    def fetch_cloud_run_details(space)
      return nil unless space.cloud_run_job_id.present?

      CloudRunService.job_details(space.cloud_run_job_id)
    rescue StandardError => e
      { error: e.message }
    end

    def fetch_cloud_run_logs(space)
      return [] unless space.cloud_run_job_id.present?

      CloudRunService.job_logs(
        space.cloud_run_job_id,
        limit: params[:limit] || 100,
        severity: params[:severity]
      )
    rescue StandardError => e
      [ { severity: "ERROR", message: "Failed to fetch logs: #{e.message}" } ]
    end

    def recent_logs(space)
      fetch_cloud_run_logs(space).first(20)
    end

    def terminate_cloud_run_job(job_id, reason)
      CloudRunService.terminate_job(job_id, reason: reason)
    rescue StandardError => e
      Rails.logger.error "[Admin] Failed to terminate Cloud Run job #{job_id}: #{e.message}"
    end
  end
end
