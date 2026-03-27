# frozen_string_literal: true

class AgentExecutionJob < ApplicationJob
  queue_as :agents

  def perform(run_id)
    run = AgentRun.find(run_id)
    return if run.cancelled? || run.complete?

    run.update!(status: :running, started_at: Time.current)
    run.add_log("Starting execution", level: :info)

    begin
      agent_record = run.agent

      # Build the agent class dynamically based on configuration
      result = execute_agent(agent_record, run)

      run.update!(
        output: result[:output],
        output_metadata: result[:metadata],
        status: :complete,
        completed_at: Time.current,
        duration_ms: ((Time.current - run.started_at) * 1000).to_i,
        input_tokens: result.dig(:usage, :input_tokens),
        output_tokens: result.dig(:usage, :output_tokens),
        total_tokens: result.dig(:usage, :total_tokens)
      )
      run.add_log("Execution completed successfully", level: :info)

    rescue => e
      run.update!(
        status: :failed,
        completed_at: Time.current,
        error_message: e.message,
        error_backtrace: e.backtrace&.first(10)&.join("\n")
      )
      run.add_log("Execution failed: #{e.message}", level: :error)
      raise
    ensure
      run.broadcast_update
    end
  end

  private

  def execute_agent(agent_record, run)
    # Check if we have ActiveAgent available
    if defined?(ActiveAgent::Base)
      execute_with_active_agent(agent_record, run)
    else
      execute_mock(agent_record, run)
    end
  end

  def execute_with_active_agent(agent_record, run)
    tool_definitions = ToolRegistry.definitions_for(agent_record.tools)
    run.add_log("Tools available: #{agent_record.tools.join(', ')}", level: :info) if agent_record.tools.any?

    # Dynamically create an agent class
    agent_class = Class.new(ActiveAgent::Base) do
      # Configure provider
      generate_with agent_record.provider.to_sym, model: agent_record.model

      define_method :perform do
        prompt instructions: agent_record.instructions if agent_record.instructions.present?
        if tool_definitions.any?
          prompt message: run.input_prompt, tools: tool_definitions
        else
          prompt message: run.input_prompt
        end
      end
    end

    # Execute the agent
    response = agent_class.perform.generate_now

    # Handle tool calls in the response
    tool_results = process_tool_calls(response, agent_record, run)

    {
      output: response.message&.content,
      metadata: {
        provider: agent_record.provider,
        model: agent_record.model,
        finish_reason: response.raw_response&.dig("choices", 0, "finish_reason"),
        tools_available: agent_record.tools,
        tool_calls: tool_results
      },
      usage: {
        input_tokens: response.usage&.[](:input_tokens) || response.usage&.[](:prompt_tokens),
        output_tokens: response.usage&.[](:output_tokens) || response.usage&.[](:completion_tokens),
        total_tokens: response.usage&.[](:total_tokens)
      }
    }
  end

  def process_tool_calls(response, agent_record, run)
    return [] unless response.respond_to?(:tool_calls) && response.tool_calls.present?

    response.tool_calls.filter_map do |tool_call|
      tool_name = tool_call["name"] || tool_call[:name]
      tool_args = tool_call["arguments"] || tool_call[:arguments] || {}

      run.add_log("Executing tool: #{tool_name}", level: :info)

      begin
        result = ToolRegistry.execute(tool_name, **tool_args.deep_symbolize_keys)
        { name: tool_name, status: "success", result: result }
      rescue BaseTool::ToolError => e
        run.add_log("Tool #{tool_name} failed: #{e.message}", level: :warn)
        { name: tool_name, status: "error", error: e.message }
      end
    end
  end

  def execute_mock(agent_record, run)
    # Mock response for development/testing
    sleep(1) # Simulate processing time
    tool_definitions = ToolRegistry.definitions_for(agent_record.tools)

    {
      output: "Mock response from #{agent_record.name} (#{agent_record.provider}/#{agent_record.model}):\n\n" \
              "Input: #{run.input_prompt}\n\n" \
              "Tools available: #{agent_record.tools.join(', ')}\n\n" \
              "This is a simulated response. Configure ActiveAgent to enable real AI responses.",
      metadata: {
        provider: agent_record.provider,
        model: agent_record.model,
        mock: true,
        tools_available: agent_record.tools,
        tool_definitions: tool_definitions.map { |t| t[:name] }
      },
      usage: {
        input_tokens: run.input_prompt.split.size * 2,
        output_tokens: 50,
        total_tokens: run.input_prompt.split.size * 2 + 50
      }
    }
  end
end
