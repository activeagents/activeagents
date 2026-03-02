# frozen_string_literal: true

require_relative "test_helper"

class TestSupervisor < Minitest::Test
  def setup
    @supervisor = Ragents::Ractor::Supervisor.new
    @supervisor.register(
      "helper",
      provider_class: Ragents::Providers::MockProvider,
      provider_opts: { responses: [{ content: "I am the helper agent." }] },
      system_prompt: "You are a helper"
    )
  end

  def test_registered_agents_accessible
    assert @supervisor.agents.key?("helper")
  end

  def test_run_registered_agent
    result = @supervisor.run("helper", "Hello")
    assert_equal "I am the helper agent.", result.content
  end

  def test_run_unregistered_agent_raises
    assert_raises(KeyError) do
      @supervisor.run("nonexistent", "Hello")
    end
  end

  def test_agent_tool_returns_tool_object
    tool = @supervisor.agent_tool("helper", description: "Ask the helper agent")
    assert_kind_of Ragents::Tool, tool
    assert_equal "call_helper_agent", tool.name
  end

  def test_agent_tool_executes_sub_agent
    tool = @supervisor.agent_tool("helper", description: "Ask the helper")
    result = tool.execute(input: "What can you do?")
    assert_equal "I am the helper agent.", result
  end

  def test_run_parallel_executes_multiple_agents
    @supervisor.register(
      "analyst",
      provider_class: Ragents::Providers::MockProvider,
      provider_opts: { responses: [{ content: "Analyst response" }] }
    )
    @supervisor.register(
      "writer",
      provider_class: Ragents::Providers::MockProvider,
      provider_opts: { responses: [{ content: "Writer response" }] }
    )

    tasks = {
      "analyst" => "Analyse this topic",
      "writer"  => "Write about this topic"
    }
    results = @supervisor.run_parallel(tasks)

    assert_equal 2, results.size
    assert_equal "Analyst response", results["analyst"].content
    assert_equal "Writer response",  results["writer"].content
  end

  def test_register_returns_supervisor_for_chaining
    result = @supervisor.register(
      "new_agent",
      provider_class: Ragents::Providers::MockProvider,
      provider_opts: { responses: [{ content: "ok" }] }
    )
    assert_equal @supervisor, result
  end

  def test_agent_tool_for_unregistered_agent_raises
    assert_raises(KeyError) do
      @supervisor.agent_tool("ghost", description: "Does not exist")
    end
  end
end
