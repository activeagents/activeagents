# frozen_string_literal: true

class SandboxChannel < ApplicationCable::Channel
  def subscribed
    session_id = params[:session_id]
    return reject unless session_id.present?

    sandbox = SandboxSession.find_by(session_id: session_id)
    return reject unless sandbox&.active?

    stream_from "sandbox_#{session_id}"
  end

  def unsubscribed
    stop_all_streams
  end
end
