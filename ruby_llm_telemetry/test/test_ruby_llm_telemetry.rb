# frozen_string_literal: true

require "test_helper"

class TestRubyLLMTelemetry < Minitest::Test
  include TelemetryTestHelpers

  def test_reports_a_completion_as_one_trace
    payload = chat_payload
    instrument("chat.ruby_llm", payload) do
      payload[:messages_after] = payload[:input_messages] + [ assistant(input: 10, output: 5) ]
    end

    trace = traces.first
    assert_equal 1, posted.size
    assert_equal "test-app", trace["service_name"]
    assert_equal %w[root llm], trace["spans"].map { |span| span["type"] }
    assert_equal({ "input" => 10, "output" => 5, "thinking" => 0, "total" => 15 }, spans_of(trace, "llm").first["tokens"])
  end

  def test_reports_unattributed_traffic_as_ruby_llm_chat
    instrument("chat.ruby_llm", chat_payload) { nil }

    assert_equal "RubyLLM::Chat.chat", traces.first.fetch("spans").first["name"]
  end

  # RubyLLM 1.x recurses through Chat#complete, so tool rounds nest inside the
  # enclosing chat event.
  def test_nested_tool_rounds_build_one_trace
    round_one = assistant(input: 10, output: 5)
    tool_result = Msg.new("tool")
    final = assistant(input: 20, output: 7)
    outer = chat_payload(tool_call: false)

    instrument("chat.ruby_llm", outer) do
      instrument("tool_call.ruby_llm", { tool_name: "search_docs", tool_call_id: "call-1", tool_arguments: { "q" => "secret" } }) { nil }

      inner = chat_payload(input_messages: outer[:input_messages] + [ round_one, tool_result ], tool_call: false)
      instrument("chat.ruby_llm", inner) { inner[:messages_after] = inner[:input_messages] + [ final ] }

      outer[:messages_after] = outer[:input_messages] + [ round_one, tool_result, final ]
    end

    trace = traces.first
    llm_span = spans_of(trace, "llm").first
    tool_span = spans_of(trace, "tool").first

    assert_equal 1, posted.size, "nested round should not post its own trace"
    assert_equal({ "input" => 30, "output" => 12, "thinking" => 0, "total" => 42 }, llm_span["tokens"])
    assert_equal "search_docs", tool_span["attributes"]["tool.name"]
    assert_equal llm_span["span_id"], tool_span["parent_span_id"]
    refute_includes posted.first.to_json, "secret", "tool arguments must not be sent"
  end

  # RubyLLM 2.x drives a flat `step until complete?` loop, so rounds are
  # siblings and tool calls fire between them.
  def test_sibling_tool_rounds_build_one_trace
    round_one = assistant(input: 10, output: 5)
    tool_result = Msg.new("tool")
    final = assistant(input: 20, output: 7)

    first_round = chat_payload(tool_call: true)
    instrument("chat.ruby_llm", first_round) { first_round[:messages_after] = first_round[:input_messages] + [ round_one ] }

    instrument("tool_call.ruby_llm", { tool_name: "search_docs", tool_call_id: "call-1" }) { nil }

    last_round = chat_payload(input_messages: first_round[:input_messages] + [ round_one, tool_result ], tool_call: false)
    instrument("chat.ruby_llm", last_round) { last_round[:messages_after] = last_round[:input_messages] + [ final ] }

    trace = traces.first
    llm_span = spans_of(trace, "llm").first

    assert_equal 1, posted.size, "intermediate round should accumulate, not post"
    assert_equal 2, llm_span["attributes"]["llm.rounds"]
    assert_equal({ "input" => 30, "output" => 12, "thinking" => 0, "total" => 42 }, llm_span["tokens"])
    assert_equal 1, spans_of(trace, "tool").size, "between-rounds tool call should join the turn"
  end

  def test_a_different_chat_flushes_a_turn_left_open
    instrument("chat.ruby_llm", chat_payload(tool_call: true)) { nil }
    instrument("chat.ruby_llm", chat_payload(chat: Object.new, tool_call: false)) { nil }

    assert_equal 2, posted.size
  end

  def test_a_raising_round_reports_an_error_trace
    assert_raises(ArgumentError) do
      instrument("chat.ruby_llm", chat_payload(tool_call: true)) { raise ArgumentError, "provider exploded" }
    end

    root_span = traces.first.fetch("spans").first
    assert_equal "ERROR", root_span["status"]
    assert_equal "ArgumentError", root_span["attributes"]["error.type"]
  end

  def test_flush_closes_a_turn_with_pending_tool_calls
    payload = chat_payload(tool_call: true)
    instrument("chat.ruby_llm", payload) { payload[:messages_after] = payload[:input_messages] + [ assistant(input: 10, output: 5) ] }
    assert_empty posted, "a round with pending tool calls stays open"

    ActiveAgents::RubyLLMTelemetry.flush!(payload)

    assert_equal 1, posted.size
  end

  def test_agent_resolver_attributes_traffic_from_the_payload
    subscribe(agent_resolver: ->(payload) { { name: "SupportBot", action: payload[:tools].any? ? "respond" : "summarize" } })

    instrument("chat.ruby_llm", chat_payload(tools: %i[search_docs])) { nil }
    instrument("chat.ruby_llm", chat_payload(chat: Object.new, tools: [])) { nil }

    assert_equal %w[SupportBot.respond SupportBot.summarize], traces.map { |trace| trace.fetch("spans").first["name"] }
  end

  def test_with_agent_names_the_trace_and_restores_the_previous_attribution
    ActiveAgents::RubyLLMTelemetry.with_agent("SupportBot", action: "respond") do
      instrument("chat.ruby_llm", chat_payload) { nil }
    end

    assert_equal "SupportBot.respond", traces.first.fetch("spans").first["name"]
    assert_nil Thread.current[ActiveAgents::RubyLLMTelemetry::AGENT_KEY]
  end
end
