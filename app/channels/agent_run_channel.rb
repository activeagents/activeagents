# frozen_string_literal: true

class AgentRunChannel < ApplicationCable::Channel
  def subscribed
    if params[:run_id]
      # Subscribe to a specific run
      stream_from "agent_run_#{params[:run_id]}"
    elsif params[:agent_id]
      # Subscribe to all runs for an agent
      stream_from "agent_runs_#{params[:agent_id]}"
    end
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
