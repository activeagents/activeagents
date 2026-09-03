# frozen_string_literal: true

class SandboxChannel < ApplicationCable::Channel
  def subscribed
    session_id = params[:session_id]
    return reject unless session_id.present?

    # Scoped like Api::SandboxesController#caller_sandboxes: run output must
    # not stream to a caller who could not read the sandbox over HTTP.
    sandbox = caller_sandboxes.find_by(session_id: session_id)
    return reject unless sandbox

    # Allow connection even if sandbox is running or ready
    stream_from "sandbox_#{session_id}"
    Rails.logger.info "[SandboxChannel] Subscribed to sandbox_#{session_id}"
  end

  def unsubscribed
    stop_all_streams
    Rails.logger.info "[SandboxChannel] Unsubscribed"
  end

  private

  # The sandbox sessions this subscriber may stream. A signed-in caller sees
  # only their own; an anonymous caller sees only the anonymous demo pool.
  def caller_sandboxes
    if current_user
      SandboxSession.where(user_id: current_user.id)
    else
      SandboxSession.anonymous
    end
  end
end
