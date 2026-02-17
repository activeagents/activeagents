# frozen_string_literal: true

module Api
  class AgentsController < BaseController
    before_action :set_agent, only: [:show, :update, :destroy, :versions, :runs, :execute, :test, :restore, :duplicate, :export]

    # GET /api/agents
    def index
      @agents = Agent.order(updated_at: :desc)

      # Filter by status
      @agents = @agents.where(status: params[:status]) if params[:status].present?

      # Filter by provider
      @agents = @agents.where(provider: params[:provider]) if params[:provider].present?

      # Search by name
      @agents = @agents.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?

      render json: {
        agents: @agents.map { |agent| agent_json(agent) },
        meta: {
          total: @agents.count,
          providers: Agent::PROVIDERS,
          preset_types: Agent::PRESET_TYPES,
          instruction_sets: Agent::INSTRUCTION_SETS,
          available_tools: Agent::AVAILABLE_TOOLS
        }
      }
    end

    # GET /api/agents/:id
    def show
      render json: {
        agent: agent_json(@agent, include_details: true),
        versions: @agent.agent_versions.recent.limit(10).map { |v| version_json(v) },
        recent_runs: @agent.agent_runs.recent.limit(5).map(&:summary)
      }
    end

    # POST /api/agents
    def create
      @agent = Agent.new(agent_params)

      if @agent.save
        render json: { agent: agent_json(@agent, include_details: true) }, status: :created
      else
        render json: { errors: @agent.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH /api/agents/:id
    def update
      if @agent.update(agent_params)
        render json: { agent: agent_json(@agent, include_details: true) }
      else
        render json: { errors: @agent.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/agents/:id
    def destroy
      @agent.destroy
      render json: { success: true }
    end

    # GET /api/agents/:id/versions
    def versions
      @versions = @agent.agent_versions.recent

      render json: {
        versions: @versions.map { |v| version_json(v, include_diff: true) }
      }
    end

    # POST /api/agents/:id/restore
    def restore
      version = @agent.agent_versions.find(params[:version_id])
      @agent.restore_from_version!(version)

      render json: { agent: agent_json(@agent, include_details: true) }
    end

    # GET /api/agents/:id/runs
    def runs
      @runs = @agent.agent_runs.recent

      # Filter by status
      @runs = @runs.where(status: params[:status]) if params[:status].present?

      # Pagination
      page = (params[:page] || 1).to_i
      per_page = (params[:per_page] || 20).to_i
      @runs = @runs.offset((page - 1) * per_page).limit(per_page)

      render json: {
        runs: @runs.map(&:summary),
        meta: {
          page: page,
          per_page: per_page,
          total: @agent.agent_runs.count
        }
      }
    end

    # POST /api/agents/:id/execute
    def execute
      run = @agent.execute(
        params[:prompt],
        **params.fetch(:params, {}).to_unsafe_h.symbolize_keys
      )

      render json: { run: run.summary }, status: :accepted
    end

    # POST /api/agents/:id/test
    def test
      run = @agent.test_execute(
        params[:prompt],
        **params.fetch(:params, {}).to_unsafe_h.symbolize_keys
      )

      render json: { run: run.summary, output: run.output }
    end

    # POST /api/agents/:id/duplicate
    def duplicate
      new_agent = @agent.dup
      new_agent.name = "#{@agent.name} (Copy)"
      new_agent.slug = nil # Will be auto-generated
      new_agent.status = :draft
      new_agent.save!

      render json: { agent: agent_json(new_agent, include_details: true) }, status: :created
    end

    # GET /api/agents/:id/export
    def export
      render json: {
        agent: agent_json(@agent, include_details: true),
        code: @agent.to_agent_class_code,
        manifest: {
          name: @agent.slug,
          version: "1.0.0",
          model: "#{@agent.provider}/#{@agent.model}",
          description: @agent.description,
          instructions: @agent.instructions,
          tools: @agent.tools,
          config: @agent.model_config
        }
      }
    end

    # GET /api/agents/presets
    def presets
      presets = Agent::PRESET_TYPES.map do |preset|
        {
          id: preset,
          name: preset.titleize,
          appearance: default_appearance_for(preset),
          suggested_tools: suggested_tools_for(preset),
          suggested_instructions: suggested_instructions_for(preset)
        }
      end

      render json: { presets: presets }
    end

    private

    def set_agent
      @agent = Agent.find(params[:id])
    end

    def agent_params
      params.require(:agent).permit(
        :name, :description, :provider, :model, :instructions,
        :preset_type, :agent_class_name, :status,
        appearance: {},
        instruction_sets: [],
        tools: [],
        mcp_servers: [],
        model_config: {},
        response_format: {}
      )
    end

    def agent_json(agent, include_details: false)
      json = {
        id: agent.id,
        name: agent.name,
        slug: agent.slug,
        description: agent.description,
        provider: agent.provider,
        model: agent.model,
        status: agent.status,
        preset_type: agent.preset_type,
        appearance: agent.appearance,
        version_count: agent.version_count,
        created_at: agent.created_at,
        updated_at: agent.updated_at
      }

      if include_details
        json.merge!(
          instructions: agent.instructions,
          instruction_sets: agent.instruction_sets,
          tools: agent.tools,
          mcp_servers: agent.mcp_servers,
          model_config: agent.model_config,
          response_format: agent.response_format,
          agent_class_name: agent.agent_class_name
        )
      end

      json
    end

    def version_json(version, include_diff: false)
      json = {
        id: version.id,
        version_number: version.version_number,
        change_summary: version.change_summary,
        created_by: version.created_by,
        created_at: version.created_at,
        is_latest: version.latest?
      }

      if include_diff && version.previous
        json[:diff] = version.diff(version.previous)
      end

      json
    end

    def default_appearance_for(preset)
      appearances = {
        "terminal" => { hat: "fedora", heldItem: "terminal", theme: "emerald" },
        "webDeveloper" => { hat: "safari", heldItem: "browser", theme: "blue" },
        "documentAnalysis" => { hat: "fedora", heldItem: "document", theme: "amber" },
        "writing" => { hat: "fedora", hatAccessory: "feather", heldItem: "scroll", theme: "purple" },
        "research" => { hat: "safari", heldItem: "magnifyingGlass", theme: "teal" },
        "playwright" => { hat: "fedora", hatAccessory: "theaterMasks", heldItem: "browser", theme: "rose" }
      }
      appearances[preset] || { theme: "default" }
    end

    def suggested_tools_for(preset)
      tools = {
        "terminal" => %w[terminal filesystem code],
        "webDeveloper" => %w[terminal filesystem code playwright],
        "documentAnalysis" => %w[filesystem search],
        "writing" => %w[edit translate],
        "research" => %w[fetch search memory],
        "playwright" => %w[playwright filesystem]
      }
      tools[preset] || []
    end

    def suggested_instructions_for(preset)
      instructions = {
        "terminal" => %w[github docker kubernetes],
        "webDeveloper" => %w[github ruby rails typescript],
        "research" => %w[github python],
        "playwright" => %w[github typescript]
      }
      instructions[preset] || []
    end
  end
end
