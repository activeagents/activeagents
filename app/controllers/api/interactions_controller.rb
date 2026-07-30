# frozen_string_literal: true

module Api
  # Read API for agent conversation contexts (solid_agent persistence),
  # backing the dashboard Interactions view.
  #
  # A context is one agent's interaction stream (AgentContext +
  # AgentMessages + AgentGenerations, recorded by SolidAgent::HasContext
  # during execution), scoped to the current user's agents.
  class InteractionsController < BaseController
    before_action :require_account!

    DEFAULT_LIMIT = 50

    # GET /api/interactions
    def index
      limit = params.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, 200)

      contexts = interactions_scope
        .includes(:contextable)
        .recent
        .limit(limit)

      message_counts = AgentMessage.where(agent_context_id: contexts.map(&:id)).group(:agent_context_id).count
      generation_counts = AgentGeneration.where(agent_context_id: contexts.map(&:id)).group(:agent_context_id).count

      render json: {
        interactions: contexts.map do |context|
          serialize_context(context).merge(
            message_count: message_counts[context.id] || 0,
            generation_count: generation_counts[context.id] || 0
          )
        end
      }
    end

    # GET /api/interactions/:id
    def show
      context = interactions_scope.find(params[:id])

      render json: {
        interaction: serialize_context(context).merge(
          instructions: context.instructions,
          messages: context.messages.chronological.map { |message| serialize_message(message) },
          generations: context.generations.order(created_at: :asc).map { |generation| serialize_generation(generation) }
        )
      }
    end

    private

    def interactions_scope
      agents = current_user.agents
      agents = agents.where(id: params[:agent_id]) if params[:agent_id].present?
      AgentContext.for_agents(agents)
    end

    def serialize_context(context)
      agent = context.contextable
      {
        id: context.id,
        agent_name: context.agent_name,
        action_name: context.action_name,
        display_name: "#{context.agent_name}##{context.action_name}",
        agent: agent.is_a?(Agent) ? { id: agent.id, name: agent.name, slug: agent.slug } : nil,
        tokens: {
          input: context.total_input_tokens,
          output: context.total_output_tokens,
          total: context.total_tokens
        },
        created_at: context.created_at.iso8601,
        last_activity_at: context.updated_at.iso8601
      }
    end

    def serialize_message(message)
      AgentMessageSerializer.call(message)
    end

    def serialize_generation(generation)
      {
        id: generation.id,
        model: generation.model,
        provider: generation.provider,
        finish_reason: generation.finish_reason,
        tokens: {
          input: generation.input_tokens,
          output: generation.output_tokens,
          total: generation.total_tokens,
          cached: generation.cached_tokens,
          thinking: generation.reasoning_tokens
        },
        cache_hit: generation.cache_hit?,
        thinking: generation.thinking?,
        duration_seconds: generation.duration_seconds,
        trace_id: generation.trace_id,
        created_at: generation.created_at.iso8601(3)
      }
    end
  end
end
