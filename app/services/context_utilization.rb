# frozen_string_literal: true

# Context-window utilization for an agent interaction: how full the window
# is, what is taking up the space, how it got there turn by turn, and how
# many turns of headroom are left.
#
# The headline number is always *measured*, never estimated. A provider
# reports `input_tokens` for every generation, and that figure is exactly
# what occupied the window at that call — so occupancy after a turn is
# `input_tokens + output_tokens` (what the next call inherits), and the
# tokens a turn added is
#
#   input_tokens[n] - (input_tokens[n-1] + output_tokens[n-1])
#
# which is precisely the user message plus tool results that landed in
# between. No tokenizer is needed for any of it.
#
# The per-source breakdown (instructions, tool schemas, MCP schemas,
# memory, messages, tool results) has no measured equivalent — nothing
# persists per-message token counts — so it is estimated with
# TokenEstimator and then *reconciled against the measured total*: whatever
# the estimate cannot account for surfaces as an explicit `unattributed`
# segment rather than being silently absorbed. Segments always sum to
# `used`, and every estimated segment is flagged so the UI can say so.
class ContextUtilization
  WARN_AT = 0.75
  CRITICAL_AT = 0.90

  # Number of trailing turns averaged for the headroom projection. Short
  # enough to react to a run that has started pulling large tool results,
  # long enough not to swing on one turn.
  PROJECTION_WINDOW = 5

  SEGMENT_LABELS = {
    "messages" => "Messages",
    "tool_results" => "Tool results",
    "instructions" => "Instructions",
    "tool_schemas" => "Tool schemas",
    "mcp_schemas" => "MCP tool schemas",
    "memory" => "Memory files",
    "unattributed" => "Unattributed"
  }.freeze

  # Full payload for one interaction: meter, per-turn growth, projection.
  def self.for_context(context)
    new(context).context_payload
  end

  # Context as it stood at one generation — "at time of call". `used` here
  # is the provider's own `input_tokens`, so this is exact.
  def self.for_generation(generation)
    new(generation.agent_context).generation_payload(generation)
  end

  # Compact per-row summaries without N+1 — one query for every context in
  # the list. Returns { context_id => { limit:, used:, peak:, pct:, ... } }.
  def self.summaries_for(contexts)
    ids = Array(contexts).map(&:id)
    return {} if ids.empty?

    rows = AgentGeneration
      .where(agent_context_id: ids)
      .order(:created_at, :id)
      .pluck(:agent_context_id, :input_tokens, :output_tokens, :model, :cached_tokens)

    rows.group_by(&:first).transform_values do |context_rows|
      occupancies = context_rows.map { |(_, input, output, _, _)| input.to_i + output.to_i }
      model = context_rows.last[3]
      limit = ModelContextWindow.for(model)
      used = occupancies.last.to_i
      peak = occupancies.max.to_i

      {
        model: model,
        limit: limit,
        window_known: ModelContextWindow.known?(model),
        used: used,
        peak: peak,
        cached: context_rows.last[4].to_i,
        turn_count: context_rows.length,
        pct: percent_of(used, limit),
        peak_pct: percent_of(peak, limit),
        state: state_for(percent_of(used, limit))
      }
    end
  end

  def self.percent_of(used, limit)
    return 0.0 if limit.to_i <= 0

    (used.to_f / limit).round(4)
  end

  def self.state_for(pct)
    return "over" if pct > 1.0
    return "critical" if pct >= CRITICAL_AT
    return "warning" if pct >= WARN_AT

    "ok"
  end

  def initialize(context)
    @context = context
  end

  def context_payload
    turns = build_turns
    measured = turns.any?
    used = measured ? turns.last[:occupancy] : estimated_total
    model = turns.last&.dig(:model) || agent&.model

    payload(used: used, model: model, measured: measured, messages: all_messages).merge(
      turns: turns,
      peak: peak_for(turns),
      truncated_turns: turns.count { |turn| turn[:truncated] },
      projection: projection_for(turns, used, ModelContextWindow.for(model)),
      cached: turns.last&.dig(:cached_tokens).to_i,
      thinking: turns.sum { |turn| turn[:thinking_tokens] }
    )
  end

  def generation_payload(generation)
    # input_tokens is the window at the moment of the call — everything the
    # provider read. Nothing here is inferred.
    used = generation.input_tokens.to_i
    at = generation.created_at
    messages = all_messages.select { |message| message.created_at <= at }
    # The turns leading up to this call, so a trace can show how its window
    # got that big rather than only how big it is.
    index = build_turns.index { |turn| turn[:generation_id] == generation.id }
    turns = index ? build_turns.first(index + 1) : []

    payload(used: used, model: generation.model, measured: true, messages: messages).merge(
      turns: turns,
      peak: peak_for(turns),
      projection: projection_for(turns, used, ModelContextWindow.for(generation.model)),
      cached: generation.cached_tokens.to_i,
      thinking: generation.reasoning_tokens.to_i,
      output_tokens: generation.output_tokens.to_i,
      finish_reason: generation.finish_reason,
      truncated: generation.truncated?,
      recorded_at: at.iso8601(3)
    )
  end

  private

  attr_reader :context

  def agent
    @agent ||= context.contextable.is_a?(Agent) ? context.contextable : nil
  end

  def all_messages
    @all_messages ||= context.messages.chronological.to_a
  end

  def payload(used:, model:, measured:, messages:)
    limit = ModelContextWindow.for(model)
    pct = self.class.percent_of(used, limit)

    {
      model: model,
      limit: limit,
      window_known: ModelContextWindow.known?(model),
      used: used,
      free: [ limit - used, 0 ].max,
      overflow: [ used - limit, 0 ].max,
      pct: pct,
      state: self.class.state_for(pct),
      measured: measured,
      warn_at: WARN_AT,
      critical_at: CRITICAL_AT,
      segments: segments_for(used, messages)
    }
  end

  # Attribution of `used` across its sources. Estimates are scaled to fit
  # the measured total; any shortfall becomes an explicit `unattributed`
  # segment so the bar always adds up to the number in the header.
  def segments_for(used, messages)
    estimates = estimate_sources(messages)
    estimated_total = estimates.values.sum

    if used <= 0
      return []
    elsif estimated_total > used && estimated_total.positive?
      scale = used.to_f / estimated_total
      estimates = estimates.transform_values { |tokens| (tokens * scale).round }
      # Rounding can leave the scaled set a token or two off; put the
      # difference on the largest segment rather than inventing a residual.
      correct_rounding!(estimates, used)
      unattributed = 0
    else
      unattributed = used - estimated_total
    end

    segments = estimates.map do |key, tokens|
      { key: key, label: SEGMENT_LABELS[key], tokens: tokens, estimated: true }
    end
    segments << { key: "unattributed", label: SEGMENT_LABELS["unattributed"], tokens: unattributed, estimated: false } if unattributed.positive?
    segments.reject { |segment| segment[:tokens].to_i <= 0 }
  end

  def correct_rounding!(estimates, used)
    drift = used - estimates.values.sum
    return if drift.zero?

    largest = estimates.max_by { |_, tokens| tokens }&.first
    estimates[largest] += drift if largest
  end

  # Ordered largest-source-first, matching how the breakdown reads.
  def estimate_sources(messages)
    conversation, tools = messages.partition { |message| message.role != "tool" }

    {
      "messages" => conversation.sum { |message| TokenEstimator.for_message(message).sum },
      "tool_results" => tools.sum { |message| TokenEstimator.for_message(message).sum },
      "instructions" => TokenEstimator.for_text(context.instructions),
      "tool_schemas" => tool_schema_tokens,
      "mcp_schemas" => mcp_schema_tokens,
      "memory" => memory_tokens
    }
  end

  def tool_schema_tokens
    return 0 unless agent

    TokenEstimator.for_json(AgentToolbox.definitions_for(agent.tools))
  end

  def mcp_schema_tokens
    return 0 unless agent

    TokenEstimator.for_json(agent.mcp_servers)
  end

  # Read-only: AgentMemory.for would create the row, and this runs on GETs.
  def memory_tokens
    return 0 unless agent

    memory = AgentMemory.find_by(memorable: agent, scope: AgentMemory::DEFAULT_SCOPE)
    memory ? TokenEstimator.for_text(memory.to_prompt) : 0
  end

  def estimated_total
    @estimated_total ||= estimate_sources(all_messages).values.sum
  end

  def build_turns
    @build_turns ||= compute_turns
  end

  def compute_turns
    generations = context.generations.order(:created_at, :id).to_a
    previous_occupancy = nil

    generations.each_with_index.map do |generation, index|
      input = generation.input_tokens.to_i
      output = generation.output_tokens.to_i
      occupancy = input + output
      # The first call's whole input is what priming cost; after that the
      # delta is what the turn added. A negative delta is real and worth
      # showing — it means history was trimmed or the stream restarted.
      added = previous_occupancy.nil? ? input : input - previous_occupancy
      previous_occupancy = occupancy

      {
        index: index,
        generation_id: generation.id,
        trace_id: generation.trace_id,
        model: generation.model,
        added: added,
        input_tokens: input,
        output_tokens: output,
        cached_tokens: generation.cached_tokens.to_i,
        thinking_tokens: generation.reasoning_tokens.to_i,
        occupancy: occupancy,
        finish_reason: generation.finish_reason,
        truncated: generation.truncated?,
        duration_seconds: generation.duration_seconds,
        at: generation.created_at.iso8601(3)
      }
    end
  end

  def peak_for(turns)
    return nil if turns.empty?

    peak = turns.max_by { |turn| turn[:occupancy] }
    limit = ModelContextWindow.for(peak[:model])

    {
      tokens: peak[:occupancy],
      pct: self.class.percent_of(peak[:occupancy], limit),
      turn_index: peak[:index],
      trace_id: peak[:trace_id]
    }
  end

  # How many more turns the window can take at the recent rate of growth.
  # Only meaningful once the interaction is actually growing.
  def projection_for(turns, used, limit)
    growth = turns.drop(1).last(PROJECTION_WINDOW).map { |turn| turn[:added] }.select(&:positive?)
    return nil if growth.empty?

    average = (growth.sum.to_f / growth.length).round
    return nil unless average.positive?

    headroom = [ limit - used, 0 ].max

    {
      avg_tokens_per_turn: average,
      turns_remaining: (headroom / average.to_f).floor,
      sampled_turns: growth.length
    }
  end
end
