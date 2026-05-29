# frozen_string_literal: true

# AgentsTool - Multi-agent orchestration
#
# Allows an agent to discover and invoke other agents, enabling
# multi-agent workflows where specialized agents handle subtasks.
#
# Usage:
#   AgentsTool.call(operation: "list")
#   AgentsTool.call(operation: "invoke", agent_name: "CodeReview", action: "perform", params: { code: "..." })
#
class AgentsTool < BaseTool
  tool_name "agents"
  description "Discover and invoke other agents for multi-agent orchestration. List available agents or delegate tasks to specialized agents."

  parameter :operation, type: "string", description: "The operation to perform", required: true, enum: %w[list invoke]
  parameter :agent_name, type: "string", description: "Name or slug of the agent to invoke (required for invoke)"
  parameter :action, type: "string", description: "The agent action to call (default: perform)", default: "perform"
  parameter :input, type: "string", description: "Input prompt to send to the invoked agent"
  parameter :params, type: "object", description: "Additional parameters to pass to the agent"

  MAX_DEPTH = 3 # Prevent infinite agent recursion

  def call(operation:, agent_name: nil, action: "perform", input: nil, params: {})
    case operation
    when "list"
      list_agents
    when "invoke"
      raise ParameterError, "agent_name is required for invoke operation" if agent_name.blank?
      raise ParameterError, "input is required for invoke operation" if input.blank?
      invoke_agent(agent_name, action, input, params)
    else
      raise ParameterError, "Unknown operation: #{operation}. Must be one of: list, invoke"
    end
  end

  private

  def list_agents
    # List ApplicationAgent subclasses
    agent_classes = list_agent_classes
    # List database-stored agents
    db_agents = list_db_agents

    {
      agent_classes: agent_classes,
      stored_agents: db_agents,
      total: agent_classes.size + db_agents.size
    }
  end

  def list_agent_classes
    return [] unless defined?(ApplicationAgent)

    ApplicationAgent.descendants.map do |klass|
      {
        name: klass.name,
        actions: klass.action_methods.to_a,
        description: klass.try(:description) || "#{klass.name} agent"
      }
    end
  rescue => e
    Rails.logger.warn("AgentsTool: Failed to list agent classes: #{e.message}")
    []
  end

  def list_db_agents
    Agent.active_agents.limit(50).map do |agent|
      {
        id: agent.id,
        name: agent.name,
        slug: agent.slug,
        description: agent.description,
        provider: agent.provider,
        model: agent.model,
        tools: agent.tools
      }
    end
  end

  def invoke_agent(agent_name, action, input, params)
    # Try to find as a Ruby agent class first
    result = invoke_agent_class(agent_name, action, input, params)
    return result if result

    # Try to find as a database-stored agent
    invoke_db_agent(agent_name, input, params)
  end

  def invoke_agent_class(agent_name, action, input, params)
    # Try to resolve as a class name
    class_name = agent_name.end_with?("Agent") ? agent_name : "#{agent_name.camelize}Agent"

    begin
      klass = class_name.constantize
    rescue NameError
      return nil
    end

    return nil unless klass < ApplicationAgent

    response = klass.with(message: input, **params.symbolize_keys).send(action).generate_now

    {
      agent: class_name,
      action: action,
      output: response&.message&.content,
      usage: {
        input_tokens: response&.usage&.[](:input_tokens),
        output_tokens: response&.usage&.[](:output_tokens)
      }
    }
  rescue => e
    raise ExecutionError, "Failed to invoke agent class #{class_name}: #{e.message}"
  end

  def invoke_db_agent(agent_name, input, params)
    agent = Agent.active_agents.find_by(slug: agent_name) ||
            Agent.active_agents.find_by(name: agent_name) ||
            Agent.active_agents.find_by(id: agent_name)

    unless agent
      raise ExecutionError, "Agent not found: #{agent_name}"
    end

    run = agent.test_execute(input, **params.symbolize_keys)

    {
      agent: agent.name,
      agent_id: agent.id,
      run_id: run.id,
      output: run.output,
      status: run.status,
      usage: {
        input_tokens: run.input_tokens,
        output_tokens: run.output_tokens,
        total_tokens: run.total_tokens
      }
    }
  end
end
