# frozen_string_literal: true

module Api
  class AgentRunsController < BaseController
    before_action :set_run, only: [ :show, :cancel ]

    # GET /api/runs/:id
    def show
      render json: {
        run: run_json(@run),
        agent: {
          id: @run.agent.id,
          name: @run.agent.name,
          slug: @run.agent.slug
        }
      }
    end

    # POST /api/runs/:id/cancel
    def cancel
      @run.cancel!
      render json: { run: @run.summary }
    end

    # GET /api/runs
    def index
      @runs = AgentRun.includes(:agent).recent

      # Filter by agent
      @runs = @runs.where(agent_id: params[:agent_id]) if params[:agent_id].present?

      # Filter by status
      @runs = @runs.where(status: params[:status]) if params[:status].present?

      # Pagination
      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 20).to_i
      @runs = @runs.offset((page - 1) * per_page).limit(per_page)

      render json: {
        runs: @runs.map { |run| run_json(run, include_agent: true) },
        meta: {
          page: page,
          per_page: per_page,
          total: AgentRun.count
        }
      }
    end

    private

    def set_run
      @run = AgentRun.find(params[:id])
    end

    def run_json(run, include_agent: false)
      json = {
        id: run.id,
        status: run.status,
        input_prompt: run.input_prompt,
        input_params: run.input_params,
        output: run.output,
        output_metadata: run.output_metadata,
        duration_ms: run.calculated_duration_ms,
        input_tokens: run.input_tokens,
        output_tokens: run.output_tokens,
        total_tokens: run.total_tokens,
        error_message: run.error_message,
        trace_id: run.trace_id,
        logs: run.logs,
        started_at: run.started_at,
        completed_at: run.completed_at,
        created_at: run.created_at
      }

      if include_agent
        json[:agent] = {
          id: run.agent.id,
          name: run.agent.name,
          slug: run.agent.slug
        }
      end

      json
    end
  end
end
