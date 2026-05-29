# frozen_string_literal: true

module Api
  class AgentContextsController < BaseController
    before_action :set_agent
    before_action :set_context, only: [ :show, :destroy, :fragments, :add_fragment ]

    # GET /api/agents/:agent_id/contexts
    def index
      contexts = @agent.agent_contexts.active.order(updated_at: :desc).limit(50)

      render json: {
        contexts: contexts.map { |c| context_json(c) },
        total: @agent.agent_contexts.active.count
      }
    end

    # GET /api/agents/:agent_id/contexts/:id
    def show
      render json: { context: context_json(@context, include_fragments: true) }
    end

    # POST /api/agents/:agent_id/contexts
    def create
      context = @agent.agent_contexts.create!(context_params)
      render json: { context: context_json(context) }, status: :created
    end

    # DELETE /api/agents/:agent_id/contexts/:id
    def destroy
      @context.destroy!
      render json: { message: "Context deleted" }
    end

    # GET /api/agents/:agent_id/contexts/:id/fragments
    def fragments
      fragments = @context.agent_fragments.includes(:agent_reasons).order(created_at: :desc)
      fragments = fragments.by_type(params[:type]) if params[:type].present?

      render json: {
        fragments: fragments.limit(100).map { |f| fragment_json(f) },
        total: fragments.count
      }
    end

    # POST /api/agents/:agent_id/contexts/:id/fragments
    def add_fragment
      fragment = @context.add_fragment(
        content: params.require(:content),
        type: params[:type] || "message",
        metadata: params[:metadata]&.to_unsafe_h || {}
      )

      render json: { fragment: fragment_json(fragment) }, status: :created
    end

    private

    def set_agent
      @agent = Agent.find(params[:agent_id])
    end

    def set_context
      @context = @agent.agent_contexts.find(params[:id])
    end

    def context_params
      params.permit(:session_id, :expires_at, state: {}, metadata: {})
    end

    def context_json(context, include_fragments: false)
      json = {
        id: context.id,
        session_id: context.session_id,
        state: context.state,
        metadata: context.metadata,
        active: context.active?,
        expires_at: context.expires_at,
        fragment_count: context.agent_fragments.count,
        created_at: context.created_at,
        updated_at: context.updated_at
      }

      if include_fragments
        json[:fragments] = context.agent_fragments
          .includes(:agent_reasons)
          .order(created_at: :desc)
          .limit(50)
          .map { |f| fragment_json(f) }
      end

      json
    end

    def fragment_json(fragment)
      {
        id: fragment.id,
        content_hash: fragment.content_hash,
        content: fragment.content.truncate(500),
        fragment_type: fragment.fragment_type,
        token_count: fragment.token_count,
        metadata: fragment.metadata,
        deterministic: fragment.deterministic?,
        reasons: fragment.agent_reasons.map { |r| reason_json(r) },
        created_at: fragment.created_at
      }
    end

    def reason_json(reason)
      {
        id: reason.id,
        reason_type: reason.reason_type,
        explanation: reason.explanation,
        confidence: reason.confidence,
        created_at: reason.created_at
      }
    end
  end
end
