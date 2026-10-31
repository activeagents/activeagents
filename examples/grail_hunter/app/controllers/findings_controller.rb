class FindingsController < ApplicationController
  before_action :set_finding, only: %i[keep dismiss]

  def index
    @status = params[:status].to_s.presence_in(Finding::STATUSES) || "new"
    @counts = current_user.findings.group(:status).count
    @findings = current_user.findings.where(status: @status).by_score.includes(:hunt)
  end

  def keep
    @finding.mark_saved!
    redirect_back_or_to findings_path, notice: "Saved."
  end

  def dismiss
    @finding.dismiss!
    redirect_back_or_to findings_path, notice: "Dismissed. The agent won't show it again."
  end

  private

  def set_finding
    @finding = current_user.findings.find(params[:id])
  end
end
