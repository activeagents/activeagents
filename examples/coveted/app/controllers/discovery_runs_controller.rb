class DiscoveryRunsController < ApplicationController
  def show
    @hunt = current_user.hunts.find(params[:hunt_id])
    @run = @hunt.discovery_runs.find(params[:id])
    @findings = @run.findings.by_score
    @contexts = @run.agent_contexts.includes(:messages, :generations)
  end
end
