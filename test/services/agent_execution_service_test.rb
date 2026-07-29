# frozen_string_literal: true

require "test_helper"

class AgentExecutionServiceTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @account = create_account(owner: @user)
    @agent = create_agent(user: @user, name: "Support Bot", provider: "openai", model: "gpt-4o-mini")
    @run = @agent.agent_runs.create!(input_prompt: "Hello there", status: :running, started_at: Time.current)
  end

  test "execute_tool routes memory tools to the agent's AgentMemory" do
    service = AgentExecutionService.new(@agent, @run)

    saved = service.execute_tool("save_memory", content: "User is on the pro plan", category: "fact")
    assert saved[:saved]

    recalled = service.execute_tool("recall_memory")
    assert_equal 1, recalled[:count]
    assert_equal "User is on the pro plan", recalled[:entries].first[:content]
    assert_equal "SupportBotAgent", recalled[:entries].first[:source_agent]

    # Persisted on the shared AgentMemory, so another agent run on the same
    # record picks it up (handoff).
    assert_equal [ "User is on the pro plan" ], @agent.memory.summary_list
  end

  test "execute_tool routes non-memory tools to AgentToolbox" do
    service = AgentExecutionService.new(@agent, @run)

    result = service.execute_tool("calculate", expression: "6*7")
    assert_equal 42, result[:result]
  end

  test "memory tool schemas are exposed when the agent enables the memory tool" do
    agent = create_agent(user: @user, name: "Rememberer", tools: %w[memory])
    run = agent.agent_runs.create!(input_prompt: "Hi", status: :running, started_at: Time.current)
    # Account provider key makes openai "available" so tool schemas are built.
    @account.provider_keys.create!(provider: "openai", credential: "sk-test")

    service = AgentExecutionService.new(agent, run)
    names = service.send(:tool_schemas).map { |d| d[:name] }
    assert_equal %w[save_memory recall_memory], names
  end

  test "runs with tools configured still succeed on the mock fallback" do
    agent = create_agent(user: @user, name: "Tool Bot", tools: %w[fetch code])
    run = agent.agent_runs.create!(input_prompt: "What is 2+2?", status: :running, started_at: Time.current)

    result = AgentExecutionService.call(agent, run)

    assert result[:output].present?
    assert_equal [], result[:metadata][:tool_calls]
  end

  test "records tool spans from the response's tool messages" do
    fake_message = Struct.new(:role, :name, :tool_call_id)
    fake_response = Struct.new(:messages)
    response = fake_response.new([
      fake_message.new("assistant", nil, nil),
      fake_message.new("tool", "calculate", "call_1"),
      fake_message.new("tool", "fetch_url", "call_2")
    ])

    service = AgentExecutionService.new(@agent, @run)
    root_span = service.send(:build_root_span)
    names = service.send(:record_tool_spans, root_span, response)

    assert_equal %w[calculate fetch_url], names
    tool_spans = root_span.children.select { |span| span.span_type.to_s == "tool" }
    assert_equal 2, tool_spans.length
    assert_equal "tool.calculate", tool_spans.first.name
  end

  test "treats the requested provider as available when the account stores a key for it" do
    @account.provider_keys.create!(provider: "openai", credential: "sk-users-own-key")

    service = AgentExecutionService.new(@agent, @run)
    assert_equal :openai, service.provider
    assert_not service.mock_fallback?
  end

  test "treats ollama as available when the account stores a host for it" do
    agent = create_agent(user: @user, name: "Local Bot", provider: "ollama", model: "llama3")
    run = agent.agent_runs.create!(input_prompt: "Hi", status: :running, started_at: Time.current)
    @account.provider_keys.create!(provider: "ollama", credential: "http://localhost:11434/v1")

    service = AgentExecutionService.new(agent, run)
    assert_equal :ollama, service.provider
  end

  test "falls back to the gem's mock provider when the requested provider is not configured" do
    result = AgentExecutionService.call(@agent, @run)

    assert result[:output].present?
    assert result[:metadata][:mock]
    assert_equal "mock", result[:metadata][:provider]
    assert_equal "openai", result[:metadata][:requested_provider]
    assert_operator result[:usage][:input_tokens], :>, 0
    assert_operator result[:usage][:output_tokens], :>, 0
  end

  test "records a telemetry trace correlated with the run" do
    AgentExecutionService.call(@agent, @run)

    trace = TelemetryTrace.for_account(@account).find_by(trace_id: @run.trace_id)
    assert trace, "expected a telemetry trace for the run's trace_id"
    assert_equal "SupportBotAgent", trace.agent_class
    assert_equal "OK", trace.status
    assert_operator trace.total_input_tokens, :>, 0
    assert_operator trace.total_duration_ms.to_f, :>, 0

    llm_span = trace.llm_spans.first
    assert llm_span
    assert_equal "mock", llm_span.dig("attributes", "llm.provider")
  end

  test "skips trace recording when the agent has no account" do
    orphan_user = create_user # no account
    agent = create_agent(user: orphan_user, name: "No Account Agent")
    run = agent.agent_runs.create!(input_prompt: "hi", status: :running, started_at: Time.current)

    assert_nothing_raised { AgentExecutionService.call(agent, run) }
    assert_equal 0, TelemetryTrace.where(trace_id: run.trace_id).count
  end

  test "records an error trace when generation fails" do
    failing_agent = create_agent(user: @user, name: "Failing Agent", provider: "mock")
    run = failing_agent.agent_runs.create!(input_prompt: "hi", status: :running, started_at: Time.current)

    service = AgentExecutionService.new(failing_agent, run)
    service.define_singleton_method(:generate!) { raise StandardError, "provider exploded" }

    assert_raises(StandardError) { service.call }

    trace = TelemetryTrace.for_account(@account).find_by(trace_id: run.trace_id)
    assert trace
    assert_equal "ERROR", trace.status
    assert_equal "provider exploded", trace.error_message
  end

  test "persists the conversation through solid_agent with trace correlation" do
    AgentExecutionService.call(@agent, @run)

    context = AgentContext.find_by(contextable: @agent)
    assert context, "expected an AgentContext for the agent"
    assert_equal "SupportBotAgent", context.agent_name
    assert_equal "ask", context.action_name

    roles = context.messages.chronological.map(&:role)
    assert_equal %w[user assistant], roles
    assert_equal @run.input_prompt, context.messages.user_messages.first.content

    generation = context.generations.last
    assert generation, "expected an AgentGeneration"
    assert_equal @run.trace_id, generation.trace_id
    assert_operator generation.input_tokens, :>, 0
    assert_equal generation.trace_id, generation.provenance["trace_id"]
    assert_operator context.reload.total_tokens, :>, 0
  end

  test "conversation stream accumulates across runs of the same agent" do
    AgentExecutionService.call(@agent, @run)
    second_run = @agent.agent_runs.create!(input_prompt: "Another question", status: :running, started_at: Time.current)
    AgentExecutionService.call(@agent, second_run)

    assert_equal 1, AgentContext.where(contextable: @agent).count
    context = AgentContext.find_by(contextable: @agent)
    assert_equal 4, context.messages.count
    assert_equal 2, context.generations.count
    assert_equal [ @run.trace_id, second_run.trace_id ], context.generations.order(:created_at).pluck(:trace_id)
  end

  test "test_execute persists run results from real execution" do
    run = @agent.test_execute("Ping")

    assert run.complete?
    assert run.output.present?
    assert_operator run.total_tokens, :>, 0
    assert_operator run.duration_ms, :>, 0
  end
end
