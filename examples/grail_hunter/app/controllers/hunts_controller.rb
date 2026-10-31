class HuntsController < ApplicationController
  before_action :set_hunt, only: %i[show edit update destroy run plan pause resume]

  def index
    @hunts = current_user.hunts.recent.includes(:findings)
    @view = findings_view
  end

  def show
    @findings = @hunt.findings.by_score
    @runs = @hunt.discovery_runs.recent.limit(20)
    @running = @hunt.discovery_runs.in_progress.exists?
    @view = findings_view
  end

  def new
    @hunt = current_user.hunts.new(frequency: "manual", currency: "USD", condition: "any")
  end

  def create
    @hunt = current_user.hunts.new(hunt_params)

    if @hunt.save
      # The first run starts right away: creating a hunt is asking for one.
      @hunt.run_now!
      redirect_to @hunt, notice: "Added. We're checking the marketplaces now. #{fee_note}"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @hunt.update(hunt_params)
      redirect_to @hunt, notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @hunt.destroy
    redirect_to hunts_path, notice: "Removed.", status: :see_other
  end

  def run
    if @hunt.discovery_runs.in_progress.exists?
      redirect_to @hunt, alert: "We're already checking. Give it a moment."
    else
      @hunt.run_now!
      redirect_to @hunt, notice: "Checking now. #{fee_note}"
    end
  end

  def plan
    result = @hunt.plan!

    if result[:ok]
      redirect_to @hunt, notice: "Search refined: we'll use #{Array(result[:plan]['queries']).size} new search terms next time."
    else
      redirect_to @hunt, alert: "We couldn't refine the search just now (#{result[:error]}). Your current search terms still apply."
    end
  end

  def pause
    @hunt.update!(status: "paused")
    redirect_to @hunt, notice: "Paused. We'll stop checking until you resume."
  end

  def resume
    @hunt.update!(status: "active")
    redirect_to @hunt, notice: "Resumed. We're back on it."
  end

  private

  def set_hunt
    @hunt = current_user.hunts.find(params[:id])
  end

  def hunt_params
    params.expect(hunt: [ :title, :brand, :category, :description, :keywords, :sizes, :max_price, :currency, :condition, :frequency ])
  end

  def findings_view
    params[:view].to_s.presence_in(%w[gallery list]) || "gallery"
  end

  def fee_note
    plan = current_user.plan
    plan.free_runs? ? "Checks are included in #{plan.name}." : "This check is #{helpers.money(plan.run_fee_cents)}."
  end
end
