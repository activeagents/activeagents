# frozen_string_literal: true

require "test_helper"

# Collapsed interaction rows in the dashboard carry two lines — what the stream
# was asked, and what it finally answered — the same pair a collapsed trace row
# shows. Both sources of an interaction have to produce them, or a list mixing
# the two reads differently depending on where each row came from. Ported from
# the actionagent engine's contract test (#111).
class Api::InteractionPreviewTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    @agent = create_agent(user: @user, name: "Support")
    sign_in_as(@user)
  end

  def create_context
    AgentContext.create!(
      contextable: @agent,
      agent_name: "SupportAgent",
      action_name: "respond",
      total_input_tokens: 40,
      total_output_tokens: 60
    )
  end

  def interactions
    get "/api/interactions"
    assert_response :success
    json_response["interactions"]
  end

  test "a context previews its opening prompt and its final answer" do
    context = create_context
    context.add_user_message("Where is order 88213?")
    context.add_assistant_message("Let me look that up.")
    context.add_user_message("Any update?")
    context.add_assistant_message("The carrier never scanned it in.")

    preview = interactions.first["preview"]

    # The ends of the stream, not its middle: the turns in between are tool
    # traffic and follow-ups that a one-line preview can't summarize.
    assert_equal "Where is order 88213?", preview["input"]
    assert_equal "The carrier never scanned it in.", preview["output"]
  end

  test "a tool-calling assistant turn is skipped for the answer" do
    context = create_context
    context.add_user_message("Where is order 88213?")
    context.add_assistant_message("The carrier never scanned it in.")
    # A turn that only carries a tool call has no prose to show.
    context.messages.create!(role: "assistant", content: "")

    assert_equal "The carrier never scanned it in.", interactions.first.dig("preview", "output")
  end

  test "previews are nil when a stream captured no content" do
    create_context

    preview = interactions.first["preview"]

    assert_nil preview["input"]
    assert_nil preview["output"]
  end

  test "each context gets its own preview" do
    first = create_context
    first.add_user_message("Where is order 88213?")
    second = create_context
    second.add_user_message("Cancel my subscription")

    previews = interactions.to_h { |row| [ row["id"], row.dig("preview", "input") ] }

    assert_equal "Where is order 88213?", previews[first.id]
    assert_equal "Cancel my subscription", previews[second.id]
  end

  test "a reported trace previews from its captured span contents" do
    TelemetryTrace.create_from_payload(reported_payload(
      "llm.prompt" => "Summarize   the\nrelease notes",
      "llm.completion" => "Three fixes and one new setting."
    ), {}, account: @account)

    preview = interactions.find { |row| row["source"] == "telemetry" }["preview"]

    # Whitespace collapses so the line stays one line whatever the prompt did.
    assert_equal "Summarize the release notes", preview["input"]
    assert_equal "Three fixes and one new setting.", preview["output"]
  end

  test "a preview is clipped rather than sending the whole conversation" do
    context = create_context
    context.add_user_message("x" * 5_000)

    input = interactions.first.dig("preview", "input")

    # Length includes the omission ActiveSupport appends.
    assert_equal InteractionPreview::LIMIT, input.length
    assert input.end_with?("...")
  end

  # The ingest endpoint stores span attributes verbatim, so a reporter that
  # sends tool.arguments or prompt.input.messages already decoded persists a
  # Hash/Array rather than a JSON string. JSON.parse raises TypeError on
  # those — which the serializer did not rescue — and one such trace 500ed
  # the whole account's Interactions list and its own detail view (#111).
  test "index and show survive a trace whose span attributes are already decoded" do
    trace = TelemetryTrace.create_from_payload(reported_payload(
      "llm.completion" => "Found it."
    ).tap { |payload|
      payload["spans"].first["attributes"]["prompt.input.messages"] = [ { "role" => "user", "content" => "Find order 1" } ]
      payload["spans"] << {
        "span_id" => "tool1", "parent_span_id" => "llm1", "name" => "tool.search",
        "type" => "tool", "duration_ms" => 50.0, "status" => "OK",
        "start_time" => Time.current.iso8601(6), "end_time" => (Time.current + 0.05).iso8601(6),
        "attributes" => { "tool.name" => "search", "tool.arguments" => { "q" => "decoded-object" }, "tool.result" => "ok" }
      }
    }, {}, account: @account)

    row = interactions.find { |r| r["id"] == "trace-#{trace.id}" }
    assert row, "the reported trace must be listed rather than 500 the index"
    assert_equal "Find order 1", row.dig("preview", "input")

    get "/api/interactions/trace-#{trace.id}"

    assert_response :success
    tool_call = json_response["interaction"]["messages"].find { |m| m["tool_calls"] }
    assert_equal({ "q" => "decoded-object" }, tool_call["tool_calls"])
  end

  private

  def reported_payload(llm_attributes)
    {
      "trace_id" => SecureRandom.hex(16),
      "service_name" => "customer-app",
      "timestamp" => Time.current.iso8601(6),
      "spans" => [
        {
          "span_id" => "root1", "parent_span_id" => nil, "name" => "ReportedAgent.respond",
          "type" => "root", "duration_ms" => 1000.0, "status" => "OK",
          "attributes" => { "agent.class" => "ReportedAgent", "agent.action" => "respond" }
        },
        {
          "span_id" => "llm1", "parent_span_id" => "root1", "name" => "llm.generate",
          "type" => "llm", "duration_ms" => 900.0, "status" => "OK",
          "attributes" => { "llm.model" => "mock-model" }.merge(llm_attributes)
        }
      ]
    }
  end
end
