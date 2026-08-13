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

    get "/dashboard/api/interactions"

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

  test "index does not leak other users' interactions" do
    other_user = create_user
    create_account(owner: other_user)
    create_interaction(agent: create_agent(user: other_user, name: "Other Agent"))

    get "/dashboard/api/interactions"

    assert_response :success
    assert_empty json_response["interactions"]
  end

  test "show returns messages and generations with trace correlation" do
    context = create_interaction

    get "/dashboard/api/interactions/#{context.id}"

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

    get "/dashboard/api/interactions/#{context.id}"

    assert_response :not_found
  end
end
