# frozen_string_literal: true

class SandboxChannel < ApplicationCable::Channel
  def subscribed
    session_id = params[:session_id]
    return reject unless session_id.present?

    sandbox = SandboxSession.find_by(session_id: session_id)
    return reject unless sandbox

    # Allow connection even if sandbox is running or ready
    stream_from "sandbox_#{session_id}"
    Rails.logger.info "[SandboxChannel] Subscribed to sandbox_#{session_id}"
  end

  def unsubscribed
    stop_all_streams
    Rails.logger.info "[SandboxChannel] Unsubscribed"
  end
end
