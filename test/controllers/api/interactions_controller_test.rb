# frozen_string_literal: true

require "test_helper"

class Api::InteractionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    @agent = create_agent(user: @user, name: "Support Bot")
    sign_in_as(@user)
  end

  def create_interaction(agent: @agent, agent_name: "SupportBotAgent")
    context = AgentContext.create!(
      contextable: agent,
      agent_name: agent_name,
      action_name: "ask",
      total_input_tokens: 40,
      total_output_tokens: 60
    )
    context.add_user_message("Hello")
    context.generations.create!(
      content: "Hi!",
      model: "mock-model",
      input_tokens: 40,
      output_tokens: 60,
      finish_reason: "stop",
      trace_id: "abc123",
      provenance: { "trace_id" => "abc123" }
    )
    context.add_assistant_message("Hi!")
    context
  end

  test "index lists the user's interaction streams with counts" do
    create_interaction

    get "/api/interactions"

    assert_response :success
    interactions = json_response["interactions"]
    assert_equal 1, interactions.length

    interaction = interactions.first
    assert_equal "SupportBotAgent#ask", interaction["display_name"]
    assert_equal "Support Bot", interaction.dig("agent", "name")
    assert_equal 2, interaction["message_count"]
    assert_equal 1, interaction["generation_count"]
    assert_equal 100, interaction.dig("tokens", "total")
  end

  test "index previews what each stream was asked and what it answered" do
    context = create_interaction
    context.add_user_message("Follow-up question")
    context.add_assistant_message("Follow-up answer")

    get "/api/interactions"

    assert_response :success
    preview = json_response["interactions"].first["preview"]

    # The opening prompt and the final answer — the middle of a stream is tool
    # traffic, which a one-line preview can't usefully summarize.
    assert_equal "Hello", preview["input"]
    assert_equal "Follow-up answer", preview["output"]
  end

  test "index previews are nil when a stream has no content" do
    AgentContext.create!(contextable: @agent, agent_name: "SupportBotAgent", action_name: "ask")

    get "/api/interactions"

    assert_response :success
    preview = json_response["interactions"].first["preview"]

    assert_nil preview["input"]
    assert_nil preview["output"]
  end

  test "index previews reported traces from their captured span contents" do
    timestamp = Time.current
    TelemetryTrace.create_from_payload(
      {
        "trace_id" => SecureRandom.hex(16),
        "service_name" => "customer-app",
        "timestamp" => timestamp.iso8601(6),
        "spans" => [
          {
            "span_id" => "r1", "parent_span_id" => nil, "name" => "ReportedAgent.respond",
            "type" => "root", "start_time" => (timestamp - 1.second).iso8601(6),
            "end_time" => timestamp.iso8601(6), "duration_ms" => 1000.0, "status" => "OK",
            "attributes" => { "agent.class" => "ReportedAgent", "agent.action" => "respond" }
          },
          {
            "span_id" => "l1", "parent_span_id" => "r1", "name" => "llm.generate",
            "type" => "llm", "start_time" => (timestamp - 0.9.seconds).iso8601(6),
            "end_time" => timestamp.iso8601(6), "duration_ms" => 900.0, "status" => "OK",
            "attributes" => {
              "llm.model" => "gpt-4o",
              "llm.prompt" => "Summarize   the\nrelease notes",
              "llm.completion" => "Three fixes and one new setting."
            }
          }
        ]
      },
      {},
      account: @account
    )

    get "/api/interactions"

    assert_response :success
    reported = json_response["interactions"].find { |row| row["source"] == "telemetry" }

    # Whitespace collapses so the preview stays one line whatever the prompt did.
    assert_equal "Summarize the release notes", reported.dig("preview", "input")
    assert_equal "Three fixes and one new setting.", reported.dig("preview", "output")
  end

  test "index does not leak other users' interactions" do
    other_user = create_user
    create_account(owner: other_user)
    create_interaction(agent: create_agent(user: other_user, name: "Other Agent"))

    get "/api/interactions"

    assert_response :success
    assert_empty json_response["interactions"]
  end

  test "show returns messages and generations with trace correlation" do
    context = create_interaction

    get "/api/interactions/#{context.id}"

    assert_response :success
    interaction = json_response["interaction"]

    assert_equal %w[user assistant], interaction["messages"].map { |m| m["role"] }
    generation = interaction["generations"].first
    assert_equal "mock-model", generation["model"]
    assert_equal "abc123", generation["trace_id"]
    assert_equal 100, generation.dig("tokens", "total")
  end

  test "show 404s for other users' interactions" do
    other_user = create_user
    context = create_interaction(agent: create_agent(user: other_user, name: "Other Agent"))

    get "/api/interactions/#{context.id}"

    assert_response :not_found
  end
end
