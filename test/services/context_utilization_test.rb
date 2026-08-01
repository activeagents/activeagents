# frozen_string_literal: true

require "test_helper"

class ContextUtilizationTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @agent = create_agent(user: @user, name: "Translation Agent", model: "gpt-4o-mini")
    @context = AgentContext.create!(
      contextable: @agent,
      agent_name: "TranslationAgent",
      action_name: "translate",
      instructions: "You translate product copy."
    )
  end

  def record_generation(input:, output:, **attributes)
    @context.generations.create!({
      model: "gpt-4o-mini",
      input_tokens: input,
      output_tokens: output,
      finish_reason: "stop"
    }.merge(attributes))
  end

  test "used is the measured occupancy the next call inherits" do
    record_generation(input: 1_000, output: 200)
    record_generation(input: 4_000, output: 500)

    payload = ContextUtilization.for_context(@context)

    assert payload[:measured]
    assert_equal 4_500, payload[:used]
    assert_equal 128_000, payload[:limit]
  end

  test "added per turn is the generation delta, not an estimate" do
    record_generation(input: 1_000, output: 200)
    # 1_200 was inherited, so this turn added 2_800.
    record_generation(input: 4_000, output: 500)

    turns = ContextUtilization.for_context(@context)[:turns]

    assert_equal 2, turns.length
    assert_equal 1_000, turns.first[:added]
    assert_equal 2_800, turns.second[:added]
    assert_equal 1_200, turns.first[:occupancy]
    assert_equal 4_500, turns.second[:occupancy]
  end

  test "a trimmed history reports a negative delta rather than hiding it" do
    record_generation(input: 10_000, output: 1_000)
    record_generation(input: 4_000, output: 500)

    turns = ContextUtilization.for_context(@context)[:turns]

    assert_equal(-7_000, turns.second[:added])
  end

  test "segments always sum to the measured total" do
    @context.add_user_message("Translate the pricing page copy to DE, FR and JA.")
    @context.add_tool_message(tool_call_id: "1", tool_name: "glossary_lookup", result: "x" * 4_000, arguments: { term: "flow" })
    @context.add_assistant_message("Done.")
    record_generation(input: 20_000, output: 2_000)

    payload = ContextUtilization.for_context(@context)

    assert_equal payload[:used], payload[:segments].sum { |segment| segment[:tokens] }
  end

  test "whatever the estimate cannot explain is surfaced as unattributed" do
    @context.add_user_message("Hi")
    record_generation(input: 50_000, output: 1_000)

    payload = ContextUtilization.for_context(@context)
    unattributed = payload[:segments].find { |segment| segment[:key] == "unattributed" }

    assert unattributed, "expected an unattributed segment"
    assert_not unattributed[:estimated]
    assert unattributed[:tokens].positive?
  end

  test "estimates are scaled down when they exceed the measured total" do
    @context.add_tool_message(tool_call_id: "1", tool_name: "export_locales", result: "x" * 200_000, arguments: {})
    record_generation(input: 5_000, output: 100)

    payload = ContextUtilization.for_context(@context)

    assert_equal 5_100, payload[:segments].sum { |segment| segment[:tokens] }
    assert_nil payload[:segments].find { |segment| segment[:key] == "unattributed" }
  end

  test "thresholds are ok, warning, critical and over" do
    assert_equal "ok", ContextUtilization.state_for(0.5)
    assert_equal "warning", ContextUtilization.state_for(0.75)
    assert_equal "critical", ContextUtilization.state_for(0.9)
    assert_equal "over", ContextUtilization.state_for(1.2)
  end

  test "an exceeded window reports overflow rather than clamping to full" do
    record_generation(input: 150_000, output: 4_000, finish_reason: "length")

    payload = ContextUtilization.for_context(@context)

    assert_equal "over", payload[:state]
    assert_equal 26_000, payload[:overflow]
    assert_equal 0, payload[:free]
    assert_equal 1, payload[:truncated_turns]
  end

  test "projection reports remaining turns at the recent rate of growth" do
    record_generation(input: 1_000, output: 0)
    record_generation(input: 11_000, output: 0)
    record_generation(input: 21_000, output: 0)

    projection = ContextUtilization.for_context(@context)[:projection]

    assert_equal 10_000, projection[:avg_tokens_per_turn]
    assert_equal 10, projection[:turns_remaining]
  end

  test "projection is nil when the interaction is not growing" do
    record_generation(input: 1_000, output: 0)

    assert_nil ContextUtilization.for_context(@context)[:projection]
  end

  test "peak reports the highest occupancy, not the latest" do
    record_generation(input: 90_000, output: 2_000)
    record_generation(input: 5_000, output: 100)

    peak = ContextUtilization.for_context(@context)[:peak]

    assert_equal 92_000, peak[:tokens]
    assert_equal 0, peak[:turn_index]
  end

  test "context at time of call uses the generation's own input tokens" do
    @context.add_user_message("First")
    generation = record_generation(input: 12_000, output: 800, cached_tokens: 4_000)
    @context.add_user_message("Later, after the call")

    payload = ContextUtilization.for_generation(generation)

    assert_equal 12_000, payload[:used]
    assert_equal 4_000, payload[:cached]
    assert payload[:measured]
  end

  test "context at time of call carries the turns leading up to it, not past it" do
    first = record_generation(input: 5_000, output: 400)
    record_generation(input: 40_000, output: 900)

    payload = ContextUtilization.for_generation(first)

    assert_equal 1, payload[:turns].length
    assert_equal first.id, payload[:turns].first[:generation_id]
  end

  test "falls back to the estimate and says so when nothing was generated" do
    @context.add_user_message("Nothing has run yet")

    payload = ContextUtilization.for_context(@context)

    assert_not payload[:measured]
    assert payload[:used].positive?
  end

  test "summaries_for batches every context in one pass" do
    other = AgentContext.create!(contextable: @agent, agent_name: "TranslationAgent", action_name: "export")
    record_generation(input: 60_000, output: 1_000)
    other.generations.create!(model: "gpt-4o-mini", input_tokens: 130_000, output_tokens: 2_000, finish_reason: "stop")

    summaries = ContextUtilization.summaries_for([ @context, other ])

    assert_equal 61_000, summaries[@context.id][:used]
    assert_equal "ok", summaries[@context.id][:state]
    assert_equal "over", summaries[other.id][:state]
    assert_equal 128_000, summaries[other.id][:limit]
  end

  test "summaries_for is empty for contexts without generations" do
    assert_empty ContextUtilization.summaries_for([ @context ])
  end
end
