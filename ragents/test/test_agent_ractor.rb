# frozen_string_literal: true

require_relative "test_helper"

# NOTE: These tests use Ractors.  In Ruby < 4.0, Ractors are still
# experimental.  Tests may emit a warning about experimental features.

class TestAgentRactor < Minitest::Test
  # ---------------------------------------------------------------------------
  # Basic agent run
  # ---------------------------------------------------------------------------

  def test_basic_run_returns_run_result
    agent = mock_agent(responses: [{ content: "I am a helpful assistant." }])
    result = agent.run("Hello")

    assert_kind_of Ragents::Ractor::RunResult, result
    assert_equal "I am a helpful assistant.", result.content
  end

  def test_run_result_has_context_snapshot
    agent = mock_agent(responses: [{ content: "Hi!" }])
    result = agent.run("Hello")

    assert result.context_snapshot.is_a?(Array)
    refute result.context_snapshot.empty?
    assert result.context_snapshot.frozen?
  end

  def test_run_adds_system_message_when_provided
    agent = mock_agent(
      responses: [{ content: "Helpful response" }],
      system_prompt: "You are a test agent"
    )
    result = agent.run("Hi")

    system_msgs = result.context_snapshot.select { |m| m.is_a?(Ragents::SystemMessage) }
    assert_equal 1, system_msgs.size
    assert_equal "You are a test agent", system_msgs.first.content
  end

  def test_run_includes_user_input_in_context
    agent = mock_agent(responses: [{ content: "Got it" }])
    result = agent.run("What is Ruby?")

    user_msgs = result.context_snapshot.select { |m| m.is_a?(Ragents::UserMessage) }
    assert_equal 1, user_msgs.size
    assert_equal "What is Ruby?", user_msgs.first.content
  end

  # ---------------------------------------------------------------------------
  # Tool calls
  # ---------------------------------------------------------------------------

  def test_single_tool_call_and_result
    responses = [
      # First call: LLM requests a tool
      {
        tool_calls: [{ id: "tc_1", name: "echo", arguments: { text: "hello" } }]
      },
      # Second call: LLM responds after seeing the tool result
      { content: "The echo returned: ECHO: hello" }
    ]

    agent = mock_agent(responses: responses, tools: [echo_tool])
    result = agent.run("Echo hello for me")

    assert_equal "The echo returned: ECHO: hello", result.content
  end

  def test_tool_result_in_context
    responses = [
      { tool_calls: [{ id: "tc_1", name: "echo", arguments: { text: "test" } }] },
      { content: "Done" }
    ]

    agent = mock_agent(responses: responses, tools: [echo_tool])
    result = agent.run("Echo test")

    tool_calls   = result.context_snapshot.select { |m| m.is_a?(Ragents::ToolCallMessage) }
    tool_results = result.context_snapshot.select { |m| m.is_a?(Ragents::ToolResultMessage) }

    assert_equal 1, tool_calls.size
    assert_equal 1, tool_results.size
    assert_equal "echo",     tool_calls.first.name
    assert_equal "ECHO: test", tool_results.first.content
  end

  def test_unknown_tool_returns_error_result
    responses = [
      { tool_calls: [{ id: "tc_1", name: "nonexistent_tool", arguments: {} }] },
      { content: "I see there was an error" }
    ]

    agent = mock_agent(responses: responses, tools: [])  # No tools registered
    # Should not raise — error is communicated as a ToolResultMessage
    result = agent.run("Call nonexistent tool")
    assert result.content
  end

  # ---------------------------------------------------------------------------
  # Context passing (parent → child)
  # ---------------------------------------------------------------------------

  def test_run_with_context_snapshot_inherits_history
    # Establish a conversation history
    prior_context = [
      Ragents::SystemMessage.new(content: "Be concise"),
      Ragents::UserMessage.new(content: "What is Ruby?"),
      Ragents::AssistantMessage.new(content: "A dynamic language.")
    ].freeze

    agent = mock_agent(responses: [{ content: "Follow-up answer" }])
    result = agent.run("Tell me more", context_snapshot: prior_context)

    all_msgs = result.context_snapshot
    assert all_msgs.any? { |m| m.is_a?(Ragents::SystemMessage) && m.content == "Be concise" }
    assert all_msgs.any? { |m| m.is_a?(Ragents::UserMessage) && m.content == "Tell me more" }
  end

  # ---------------------------------------------------------------------------
  # Max iterations guard
  # ---------------------------------------------------------------------------

  def test_raises_when_max_iterations_exceeded
    # Keep returning tool calls to trigger the loop
    infinite_tool_responses = Array.new(20) do
      { tool_calls: [{ id: "tc_1", name: "echo", arguments: { text: "loop" } }] }
    end

    agent = mock_agent(
      responses: infinite_tool_responses,
      tools: [echo_tool],
      max_iterations: 3
    )

    assert_raises(RuntimeError) do
      agent.run("Run forever")
    end
  end

  # ---------------------------------------------------------------------------
  # Parallel runs
  # ---------------------------------------------------------------------------

  def test_run_parallel_returns_results_in_order
    agent = mock_agent(responses: [{ content: "Answer" }])
    inputs = ["Q1", "Q2", "Q3", "Q4", "Q5"]
    results = agent.run_parallel(inputs)

    assert_equal 5, results.size
    results.each_with_index do |r, i|
      assert_kind_of Ragents::Ractor::RunResult, r,
                     "Result #{i} should be a RunResult"
    end
  end

  def test_run_parallel_each_has_independent_context
    agent = mock_agent(responses: [{ content: "Response" }])
    inputs = ["Q1", "Q2"]
    results = agent.run_parallel(inputs)

    msgs_0 = results[0].context_snapshot.select { |m| m.is_a?(Ragents::UserMessage) }
    msgs_1 = results[1].context_snapshot.select { |m| m.is_a?(Ragents::UserMessage) }

    assert_equal "Q1", msgs_0.first.content
    assert_equal "Q2", msgs_1.first.content
  end
end
