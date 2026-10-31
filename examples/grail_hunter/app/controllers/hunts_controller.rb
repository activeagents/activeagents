class HuntsController < ApplicationController
  before_action :set_hunt, only: %i[show edit update destroy run plan pause resume]

  def index
    @hunts = current_user.hunts.recent.includes(:findings)
  end

  def show
    @findings = @hunt.findings.by_score
    @runs = @hunt.discovery_runs.recent.limit(20)
    @running = @hunt.discovery_runs.in_progress.exists?
  end

  def new
    @hunt = current_user.hunts.new(frequency: "manual", currency: "USD", condition: "any")
  end

  def create
    @hunt = current_user.hunts.new(hunt_params)

    if @hunt.save
      # The first run starts right away: creating a hunt is asking for one.
      @hunt.run_now!
      redirect_to @hunt, notice: "Hunt created. The agent is on it. #{fee_note}"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @hunt.update(hunt_params)
      redirect_to @hunt, notice: "Hunt updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @hunt.destroy
    redirect_to hunts_path, notice: "Hunt deleted.", status: :see_other
  end

  def run
    if @hunt.discovery_runs.in_progress.exists?
      redirect_to @hunt, alert: "A run is already in progress."
    else
      @hunt.run_now!
      redirect_to @hunt, notice: "Run queued. #{fee_note}"
    end
  end

  def plan
    result = @hunt.plan!

    if result[:ok]
      redirect_to @hunt, notice: "Search plan updated: #{Array(result[:plan]['queries']).size} queries from the planner agent."
    else
      redirect_to @hunt, alert: "The planner returned no usable plan (#{result[:error]}). " \
                                "With the mock provider that is expected; set a provider key for a real plan."
    end
  end

  def pause
    @hunt.update!(status: "paused")
    redirect_to @hunt, notice: "Hunt paused. Scheduled runs stop until you resume it."
  end

  def resume
    @hunt.update!(status: "active")
    redirect_to @hunt, notice: "Hunt resumed."
  end

  private

  def set_hunt
    @hunt = current_user.hunts.find(params[:id])
  end

  def hunt_params
    params.expect(hunt: [ :title, :brand, :category, :description, :keywords, :sizes, :max_price, :currency, :condition, :frequency ])
  end

  def fee_note
    plan = current_user.plan
    plan.free_runs? ? "No per-run fee on the #{plan.name} plan." : "Fee: #{helpers.money(plan.run_fee_cents)}."
  end
end
