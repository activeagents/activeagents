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
    # Dynamically create an agent class
    agent_class = Class.new(ActiveAgent::Base) do
      # Configure provider
      generate_with agent_record.provider.to_sym, model: agent_record.model

      define_method :perform do
        prompt instructions: agent_record.instructions if agent_record.instructions.present?
        prompt message: run.input_prompt
      end
    end

    # Execute the agent
    response = agent_class.perform.generate_now

    {
      output: response.message&.content,
      metadata: {
        provider: agent_record.provider,
        model: agent_record.model,
        finish_reason: response.raw_response&.dig("choices", 0, "finish_reason")
      },
      usage: {
        input_tokens: response.usage&.[](:input_tokens) || response.usage&.[](:prompt_tokens),
        output_tokens: response.usage&.[](:output_tokens) || response.usage&.[](:completion_tokens),
        total_tokens: response.usage&.[](:total_tokens)
      }
    }
  end

  def execute_mock(agent_record, run)
    # Mock response for development/testing
    sleep(1) # Simulate processing time

    {
      output: "Mock response from #{agent_record.name} (#{agent_record.provider}/#{agent_record.model}):\n\n" \
              "Input: #{run.input_prompt}\n\n" \
              "This is a simulated response. Configure ActiveAgent to enable real AI responses.",
      metadata: {
        provider: agent_record.provider,
        model: agent_record.model,
        mock: true
      },
      usage: {
        input_tokens: run.input_prompt.split.size * 2,
        output_tokens: 50,
        total_tokens: run.input_prompt.split.size * 2 + 50
      }
    }
  end
end
