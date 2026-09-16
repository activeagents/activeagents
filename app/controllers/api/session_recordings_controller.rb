# frozen_string_literal: true

module Api
  # The landing page's session-replay demo records a visitor's own browser
  # session so they can watch it back: start_user_session mints a recording,
  # record_action appends to it, complete closes it. Visitors are anonymous,
  # so these three endpoints stay on this app rather than on the mounted
  # dashboard engine, which authenticates every recording endpoint on purpose
  # (recordings carry a replayable timeline of a real browser session).
  # Playback, listing, export and handoff of recordings are the engine's, at
  # /dashboard/api/session_recordings, for signed-in owners only.
  #
  # The recording itself is the engine's model (SessionRecording is an alias
  # of ActionAgent::SessionRecording), so a visitor who signs up sees the
  # session in the dashboard once UserSessionClaimer stamps it with them.
  class SessionRecordingsController < BaseController
    allow_unauthenticated_access only: [ :start_user_session, :record_action, :complete_session ]

    # allow_unauthenticated_access skips require_authentication, which is
    # also the only thing that populates Current.session — so a signed-in
    # visitor was anonymous on these actions. Identify them without
    # requiring them, so their recordings carry their account and the
    # ownership gate below recognises them.
    before_action :resume_session
    before_action :set_writable_recording, only: [ :record_action, :complete_session ]

    # The write token start_user_session hands the browser. Anonymous writes
    # to a recording are accepted only with the token minted for that
    # recording, so a caller who merely knows (or guesses) an id cannot
    # append actions to, or force-complete, someone else's live session.
    WRITE_TOKEN_PURPOSE = :session_recording_write
    WRITE_TOKEN_TTL = 24.hours

    # POST /api/session_recordings/start_user_session
    def start_user_session
      recording = SessionRecording.start_user_session!(
        visitor_id: params[:visitor_id] || generate_visitor_id,
        parent_demo_id: params[:parent_demo_id],
        page_url: params[:page_url],
        owner: current_user
      )

      # Set user agent from request. A signed-in visitor's recording is
      # stamped with their account as well as owned by them, the key
      # UserSessionClaimer and the ownership gate below resolve through.
      # String keys: the stored metadata is string-keyed, and merging symbols
      # into it wrote a second "user_agent" that json 3.0 refuses to encode.
      request_metadata = {
        "user_agent" => request.user_agent,
        "ip_hash" => Digest::SHA256.hexdigest(request.remote_ip.to_s)[0..16]
      }
      if (account = current_user&.primary_account)
        request_metadata["account_id"] = account.id.to_s
      end
      recording.update!(metadata: recording.metadata.merge(request_metadata))

      # Record the handoff action
      recording.record_action!(
        action_type: "handoff",
        value: "User took over from agent demo",
        metadata: {
          source: "lander_demo",
          step: params[:step] || 4
        }
      )

      render json: {
        recording_id: recording.id,
        visitor_id: recording.metadata["visitor_id"],
        recording_token: write_token_for(recording),
        message: "User session started"
      }, status: :created
    end

    # POST /api/session_recordings/:id/record_action
    def record_action
      unless @recording.recording?
        render json: { error: "Recording already completed" }, status: :unprocessable_entity
        return
      end

      action = @recording.record_action!(
        action_type: params[:action_type],
        selector: params[:selector],
        value: params[:value],
        metadata: params[:metadata]&.to_unsafe_h || {}
      )

      render json: {
        action_id: action.id,
        sequence: action.sequence,
        timestamp_ms: action.timestamp_ms
      }
    end

    # POST /api/session_recordings/:id/complete
    def complete_session
      unless @recording.recording?
        render json: { error: "Recording already completed" }, status: :unprocessable_entity
        return
      end

      # Record the completion action
      @recording.record_action!(
        action_type: "completion",
        value: params[:completion_type] || "session_end",
        metadata: {
          email_submitted: params[:email_submitted],
          success: params[:success]
        }
      )

      @recording.complete!

      render json: {
        recording_id: @recording.id,
        status: @recording.status,
        action_count: @recording.action_count,
        duration_ms: @recording.duration_ms
      }
    end

    private

    # A recording may be written by whoever may manage it (its owner, their
    # account, or an admin) or by the anonymous browser that started it,
    # which proves that with the token start_user_session issued.
    #
    # Not found and not writable answer identically (404), so a real id
    # cannot be told from a bogus one by probing: answering 422 "already
    # completed" for any real id and 404 for the rest would be an oracle
    # over the id space.
    def set_writable_recording
      @recording = SessionRecording.find_by(id: params[:id])
      return not_found if @recording.nil?
      return if can_manage_recording?(@recording)
      return if write_token_valid?(@recording)

      not_found
    end

    def write_token_for(recording)
      write_token_verifier.generate(recording.id, purpose: WRITE_TOKEN_PURPOSE, expires_in: WRITE_TOKEN_TTL)
    end

    # Accepted in the JSON body (the lander's fetch calls) or as a header, so
    # a client that cannot add a body field still has a way in.
    def write_token_valid?(recording)
      token = params[:recording_token].presence || request.headers["X-Recording-Token"].presence
      return false unless token.is_a?(String)

      write_token_verifier.verified(token, purpose: WRITE_TOKEN_PURPOSE) == recording.id
    end

    def write_token_verifier
      Rails.application.message_verifier(WRITE_TOKEN_PURPOSE)
    end

    # The same reachability the engine grants a signed-in reader: the owner
    # (the engine writes the owner column), a member of the account the
    # recording was stamped with, whoever opened the sandbox it records, and
    # an admin.
    def can_manage_recording?(recording)
      return false unless current_user
      return true if current_user.admin?
      return true if recording.owner == current_user

      if (account = current_user.primary_account)
        return true if recording.metadata["account_id"].to_s == account.id.to_s
      end

      session = recording.sandbox_session
      session.present? && session.owner.present? && session.owner == current_user
    end

    def generate_visitor_id
      # Generate a stable visitor ID based on IP and user agent
      fingerprint = "#{request.remote_ip}:#{request.user_agent}"
      "v_#{Digest::SHA256.hexdigest(fingerprint)[0..16]}"
    end
  end
end
