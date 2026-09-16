# frozen_string_literal: true

module Api
  # CRUD + execution for agent evaluations, backing the dashboard
  # Evaluations view. Scoped to the current user's agents.
  class EvaluationsController < BaseController
    before_action :require_account!

    # Default criteria used when none are supplied — all rule-based, so a
    # new evaluation produces real scores without provider credentials.
    DEFAULT_CRITERIA = [
      { "key" => "response_present", "type" => "response_present", "config" => {} },
      { "key" => "response_length", "type" => "min_length", "config" => { "chars" => 40 } },
      { "key" => "latency", "type" => "max_latency_ms", "config" => { "ms" => 5000 } },
      { "key" => "token_budget", "type" => "token_budget", "config" => { "output_tokens" => 1000 } }
    ].freeze

    # Runs listed per evaluation on GET /api/evaluations/:id.
    RUN_HISTORY_LIMIT = 20

    # GET /api/evaluations
    # agent_id scopes to one agent. The filter has to happen before the limit:
    # the agent page reads this endpoint, and filtering an account-wide page of
    # 50 client-side hides an agent whose evaluations are not among the account's
    # 50 most recent. The scope is already restricted to the current user's
    # agents, so an id outside it simply returns nothing.
    def index
      scope = evaluations_scope
      scope = scope.where(agent_id: params[:agent_id]) if params[:agent_id].present?
      evaluations = scope.includes(:agent, :evaluation_runs).recent.limit(50)

      render json: { evaluations: evaluations.map { |evaluation| serialize(evaluation) } }
    end

    # GET /api/evaluations/:id
    def show
      evaluation = evaluations_scope.find(params[:id])
      runs_count = evaluation.evaluation_runs.count
      runs = evaluation.evaluation_runs.recent.limit(RUN_HISTORY_LIMIT).to_a

      render json: {
        evaluation: serialize(evaluation).merge(
          runs: runs.each_with_index.map { |run, index| serialize_run(run, number: runs_count - index) }
        )
      }
    end

    # POST /api/evaluations
    def create
      agent = current_user.agents.find(params.require(:evaluation)[:agent_id])

      judge_kind = evaluation_params[:judge_kind].presence || "rules"
      config = {}
      config["compare_models"] = compare_models_param if compare_models_param.any?

      evaluation = agent.evaluations.new(
        name: evaluation_params[:name],
        judge_kind: judge_kind,
        judge_model: evaluation_params[:judge_model],
        sample_size: evaluation_params[:sample_size].presence || 20,
        # judge_defined starts with no criteria — the judge authors the
        # KPIs on the first run.
        criteria: judge_kind == "judge_defined" ? explicit_criteria : normalized_criteria,
        config: config
      )

      if evaluation.save
        evaluation.run!
        render json: { evaluation: serialize(evaluation.reload) }, status: :created
      else
        render json: { errors: evaluation.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # POST /api/evaluations/:id/run
    def run
      evaluation = evaluations_scope.find(params[:id])
      run = evaluation.run!
      evaluation.reload

      render json: {
        evaluation: serialize(evaluation),
        run: serialize_run(run, number: evaluation.evaluation_runs.count)
      }
    end

    # DELETE /api/evaluations/:id
    def destroy
      evaluations_scope.find(params[:id]).destroy!
      head :no_content
    end

    private

    def evaluations_scope
      Evaluation.joins(:agent).where(agents: { user_id: current_user.id })
    end

    def evaluation_params
      params.require(:evaluation).permit(:agent_id, :name, :judge_kind, :judge_model, :sample_size)
    end

    def normalized_criteria
      explicit_criteria.presence || DEFAULT_CRITERIA.deep_dup
    end

    def explicit_criteria
      raw = params[:evaluation][:criteria]
      return [] if raw.blank?

      raw.map do |criterion|
        criterion.permit(:key, :type, config: {}).to_h.tap do |c|
          c["key"] = c["key"].presence || c["type"]
          c["config"] ||= {}
        end
      end
    end

    def compare_models_param
      Array(params[:evaluation][:compare_models]).map(&:to_s).reject(&:blank?)
    end

    def serialize(evaluation)
      # size reads the preloaded association on index and COUNTs elsewhere.
      runs_count = evaluation.evaluation_runs.size
      latest, previous = recent_runs(evaluation, 2)

      {
        id: evaluation.id,
        name: evaluation.name,
        agent: { id: evaluation.agent.id, name: evaluation.agent.name, slug: evaluation.agent.slug },
        judge_kind: evaluation.judge_kind,
        judge_model: evaluation.judge_model,
        criteria: evaluation.criteria,
        compare_models: evaluation.compare_models,
        config: evaluation.config,
        sample_size: evaluation.sample_size,
        created_at: evaluation.created_at.iso8601,
        runs_count: runs_count,
        latest_run: latest ? serialize_run(latest, number: runs_count) : nil,
        # Just enough of the run before it for the list to show movement
        # ("+3 passed vs #2") without a request per evaluation.
        previous_run: previous ? serialize_run_summary(previous, number: runs_count - 1) : nil
      }
    end

    # Newest first. Sorts the preloaded association when index loaded it
    # rather than issuing one ORDER BY query per evaluation.
    def recent_runs(evaluation, limit)
      runs = evaluation.evaluation_runs
      if runs.loaded?
        runs.sort_by { |run| [ run.created_at, run.id ] }.reverse.first(limit)
      else
        runs.recent.limit(limit).to_a
      end
    end

    # number is the run's position in its evaluation's history, oldest = 1,
    # so the dashboard can say "Run #3" and "vs #2".
    def serialize_run(run, number: nil)
      serialize_run_summary(run, number: number).merge(
        scores: run.scores,
        error_message: run.error_message
      )
    end

    def serialize_run_summary(run, number: nil)
      {
        id: run.id,
        number: number,
        status: run.status,
        average_score: run.average_score,
        samples_evaluated: run.samples_evaluated,
        samples_passed: run.samples_passed,
        completed_at: run.completed_at&.iso8601,
        created_at: run.created_at.iso8601
      }
    end
  end
end
