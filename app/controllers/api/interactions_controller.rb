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
    MAX_WINDOW_MINUTES = 60 * 24 * 90

    # GET /api/interactions
    def index
      limit = params.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, 200)

      contexts = interactions_scope
        .includes(:contextable)
        .then { |scope| window_minutes ? scope.where(updated_at: window_minutes.minutes.ago..) : scope }
        .recent
        .limit(limit)

      message_counts = AgentMessage.where(agent_context_id: contexts.map(&:id)).group(:agent_context_id).count
      generation_counts = AgentGeneration.where(agent_context_id: contexts.map(&:id)).group(:agent_context_id).count
      # Latest model per context, so list rows can gauge context-window
      # pressure without loading generations.
      latest_models = AgentGeneration
        .where(agent_context_id: contexts.map(&:id))
        .select("DISTINCT ON (agent_context_id) agent_context_id, model")
        .order("agent_context_id, created_at DESC")
        .to_h { |generation| [ generation.agent_context_id, generation.model ] }

      previews = message_previews(contexts.map(&:id))

      persisted = contexts.map do |context|
        serialize_context(context).merge(
          source: "platform",
          model: latest_models[context.id],
          message_count: message_counts[context.id] || 0,
          generation_count: generation_counts[context.id] || 0,
          preview: previews[context.id] || { input: nil, output: nil }
        )
      end

      reported = reported_traces(limit).map { |trace| TraceInteractionSerializer.summary(trace) }

      render json: {
        interactions: (persisted + reported).sort_by { |row| row[:last_activity_at].to_s }.reverse.first(limit)
      }
    end

    # GET /api/interactions/:id
    def show
      if (trace_id = params[:id].to_s[/\Atrace-(\d+)\z/, 1])
        trace = current_account.telemetry_traces.find(trace_id)
        return render json: { interaction: TraceInteractionSerializer.detail(trace) }
      end

      context = interactions_scope.find(params[:id])

      render json: {
        interaction: serialize_context(context).merge(
          source: "platform",
          instructions: context.instructions,
          messages: context.messages.chronological.map { |message| serialize_message(message) },
          generations: context.generations.order(created_at: :asc).map { |generation| serialize_generation(generation) }
        )
      }
    end

    private

    # What each stream opened with and what it finally answered, so a collapsed
    # interaction row says what it was about — the same two lines a collapsed
    # trace row shows. Two grouped queries rather than loading every message:
    # the list is 50 streams deep and only needs the ends of each.
    def message_previews(context_ids)
      return {} if context_ids.empty?

      first_input = edge_messages(context_ids, "user", :asc)
      last_output = edge_messages(context_ids, "assistant", :desc)

      context_ids.index_with do |id|
        {
          input: InteractionPreview.line(first_input[id]),
          output: InteractionPreview.line(last_output[id])
        }
      end
    end

    def edge_messages(context_ids, role, direction)
      AgentMessage
        .where(agent_context_id: context_ids, role: role)
        .where.not(content: [ nil, "" ])
        .select("DISTINCT ON (agent_context_id) agent_context_id, content")
        .order(agent_context_id: :asc, created_at: direction)
        .to_h { |message| [ message.agent_context_id, message.content ] }
    end

    # Agents executing outside the platform never write solid_agent contexts —
    # they only report traces. Every reported trace is an interaction: one run
    # of one agent. Traces without captured content still show their tool calls,
    # timings, and generation metadata, so filtering on the presence of a
    # prompt would hide most runs (locally: 9 of 11) and make the per-agent
    # counts disagree with Traces for the same window.
    def reported_traces(limit)
      scope = current_account.telemetry_traces.where.not(agent_class: nil)
      scope = scope.where(timestamp: window_minutes.minutes.ago..) if window_minutes
      # Honor the agent filter the persisted side already applies: without
      # this, a per-agent view listed every agent's reported traffic, and an
      # agent whose traces are all SDK-reported showed nothing of its own.
      scope = scope.merge(traces_for_agent(params[:agent_id])) if params[:agent_id].present?
      scope.order(timestamp: :desc).limit(limit)
    end

    # Traces belong to an agent by foreign key once AgentRegistrar attributes
    # them; older rows predate that, so fall back to the class name.
    def traces_for_agent(agent_id)
      agent = current_user.agents.find_by(id: agent_id)
      return TelemetryTrace.none unless agent

      TelemetryTrace.where(agent_id: agent.id)
        .or(TelemetryTrace.where(agent_id: nil, agent_class: agent.telemetry_agent_class))
    end

    # The dashboard-wide time window, shared with Traces. Absent means "all".
    def window_minutes
      return @window_minutes if defined?(@window_minutes)

      raw = params[:minutes].presence
      @window_minutes = raw ? raw.to_i.clamp(1, MAX_WINDOW_MINUTES) : nil
    end

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
