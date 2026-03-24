# frozen_string_literal: true

module Api
  class SessionRecordingsController < BaseController
    before_action :set_recording, only: [:show, :actions, :snapshot, :export, :handoff]

    # GET /api/session_recordings
    # List recordings with optional filters
    def index
      recordings = SessionRecording.recent

      # Filter by status
      recordings = recordings.where(status: params[:status]) if params[:status].present?

      # Filter by agent
      if params[:agent_id].present?
        recordings = recordings.joins(:agent_run)
                               .where(agent_runs: { agent_id: params[:agent_id] })
      end

      # Filter by sandbox session
      if params[:sandbox_session_id].present?
        recordings = recordings.where(sandbox_session_id: params[:sandbox_session_id])
      end

      # Pagination
      page = (params[:page] || 1).to_i
      per_page = [(params[:per_page] || 20).to_i, 100].min
      offset = (page - 1) * per_page

      total = recordings.count
      recordings = recordings.offset(offset).limit(per_page)

      render json: {
        recordings: recordings.map { |r| recording_summary(r) },
        pagination: {
          page: page,
          per_page: per_page,
          total: total,
          total_pages: (total.to_f / per_page).ceil
        }
      }
    end

    # GET /api/session_recordings/recent
    # Get recent recordings for the current user
    def recent
      recordings = SessionRecording.recent.limit(10)

      # If user is logged in, filter to their recordings
      if current_user
        recordings = recordings.joins(:agent_run)
                               .where(agent_runs: { user_id: current_user.id })
      end

      render json: {
        recordings: recordings.map { |r| recording_summary(r) }
      }
    end

    # GET /api/session_recordings/demo
    # Get the pre-recorded demo session for the lander
    def demo
      # Find the featured demo recording or create a placeholder
      demo_recording = SessionRecording.find_by(name: "lander_demo") ||
                       SessionRecording.completed.order(:created_at).first

      if demo_recording
        render json: {
          recording: recording_detail(demo_recording),
          handoff_available: demo_recording.metadata["handoff_state"].present?
        }
      else
        render json: {
          recording: nil,
          message: "No demo recording available"
        }
      end
    end

    # GET /api/session_recordings/:id
    # Get full recording details for playback
    def show
      render json: {
        recording: recording_detail(@recording)
      }
    end

    # GET /api/session_recordings/:id/actions
    # Get the action timeline for playback
    def actions
      actions = @recording.recording_actions.ordered

      # Support pagination for large recordings
      if params[:after_sequence].present?
        actions = actions.where("sequence > ?", params[:after_sequence].to_i)
      end

      limit = [params[:limit]&.to_i || 100, 500].min
      actions = actions.limit(limit)

      render json: {
        actions: actions.map(&:as_json_for_api),
        has_more: actions.count == limit,
        total_actions: @recording.action_count
      }
    end

    # GET /api/session_recordings/:id/snapshot/:action_id
    # Get a specific snapshot (screenshot or DOM)
    def snapshot
      action = @recording.recording_actions.find(params[:action_id])

      snapshot_type = params[:type] || "screenshot"

      case snapshot_type
      when "screenshot"
        url = action.screenshot_url
        render json: { url: url, type: "screenshot" }
      when "dom"
        content = action.dom_snapshot_content
        render json: { content: content, type: "dom" }
      else
        render json: { error: "Unknown snapshot type" }, status: :bad_request
      end
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Action not found" }, status: :not_found
    end

    # POST /api/session_recordings/:id/export
    # Export recording as VCR cassette
    def export
      format = params[:format] || "json"

      cassette = build_cassette(@recording, format)

      render json: {
        cassette: cassette,
        filename: "#{@recording.name}_recording.#{format}"
      }
    end

    # POST /api/session_recordings/:id/handoff
    # Get handoff state to continue where agent left off
    def handoff
      handoff_state = @recording.metadata["handoff_state"]

      unless handoff_state
        render json: { error: "No handoff state available" }, status: :unprocessable_entity
        return
      end

      # Create a new recording for the user's continuation
      continuation = SessionRecording.create!(
        sandbox_session: @recording.sandbox_session,
        agent_run: @recording.agent_run,
        name: "#{@recording.name}_continuation",
        status: :recording,
        metadata: {
          parent_recording_id: @recording.id,
          handoff_from: @recording.action_count,
          started_at: Time.current.iso8601,
          user_id: current_user&.id
        }
      )

      render json: {
        handoff_state: handoff_state,
        continuation_recording_id: continuation.id,
        parent_recording: recording_summary(@recording),
        message: "Ready to continue from action #{@recording.action_count}"
      }
    end

    # DELETE /api/session_recordings/:id
    def destroy
      @recording = SessionRecording.find(params[:id])

      # Only allow deletion of own recordings (or any if admin)
      unless can_manage_recording?(@recording)
        render json: { error: "Not authorized" }, status: :forbidden
        return
      end

      @recording.destroy!
      render json: { message: "Recording deleted" }
    end

    private

    def set_recording
      @recording = SessionRecording.find(params[:id])
    end

    def can_manage_recording?(recording)
      return true if current_user&.admin?

      if recording.agent_run
        recording.agent_run.user_id == current_user&.id
      elsif recording.sandbox_session
        recording.sandbox_session.user_id == current_user&.id
      else
        false
      end
    end

    def recording_summary(recording)
      {
        id: recording.id,
        name: recording.name,
        status: recording.status,
        action_count: recording.action_count,
        duration_ms: recording.duration_ms,
        created_at: recording.created_at.iso8601,
        thumbnail_url: first_screenshot_url(recording),
        agent_name: recording.agent_run&.agent&.name,
        sandbox_type: recording.sandbox_session&.sandbox_type
      }
    end

    def recording_detail(recording)
      {
        id: recording.id,
        name: recording.name,
        status: recording.status,
        action_count: recording.action_count,
        duration_ms: recording.duration_ms,
        metadata: safe_metadata(recording.metadata),
        created_at: recording.created_at.iso8601,
        updated_at: recording.updated_at.iso8601,
        timeline: recording.timeline,
        handoff_state: recording.metadata["handoff_state"],
        agent: recording.agent_run&.agent&.slice(:id, :name),
        sandbox_session: recording.sandbox_session&.summary
      }
    end

    def first_screenshot_url(recording)
      action = recording.recording_actions.with_screenshots.first
      action&.screenshot_url(expires_in: 1.hour)
    end

    def safe_metadata(metadata)
      # Remove sensitive data from metadata
      metadata.except("cookies", "session_storage", "local_storage")
    end

    def build_cassette(recording, format)
      cassette = {
        name: recording.name,
        recorded_at: recording.created_at.iso8601,
        duration_ms: recording.duration_ms,
        action_count: recording.action_count,
        actions: recording.recording_actions.ordered.map do |action|
          {
            type: action.action_type,
            sequence: action.sequence,
            timestamp_ms: action.timestamp_ms,
            selector: action.selector,
            value: action.value,
            metadata: action.metadata
          }
        end
      }

      # Include screenshots as base64 if requested
      if params[:include_screenshots] == "true"
        cassette[:actions].each_with_index do |action_data, i|
          action = recording.recording_actions.find_by(sequence: action_data[:sequence])
          if action&.screenshot_key
            snapshot = RecordingSnapshot.find_by(storage_key: action.screenshot_key)
            if snapshot&.file&.attached?
              action_data[:screenshot_base64] = Base64.encode64(snapshot.file.download)
            end
          end
        end
      end

      cassette
    end
  end
end
