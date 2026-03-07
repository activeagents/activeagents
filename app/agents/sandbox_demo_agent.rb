# frozen_string_literal: true

# SandboxDemoAgent - Multi-provider agent for sandbox demonstrations
#
# This agent can be configured with different providers for comparison testing.
#
# Usage:
#   # Synchronous (blocking)
#   response = SandboxDemoAgent.with(task: "Write a haiku", provider: "anthropic").ask.generate_now
#
#   # Asynchronous (background job)
#   SandboxDemoAgent.with(task: "Write a haiku", provider: "anthropic", sandbox_session_id: 123, run_id: "uuid")
#                   .ask
#                   .generate_later
#
class SandboxDemoAgent < ApplicationAgent
  # Provider-specific configurations
  PROVIDER_CONFIGS = {
    "anthropic" => { provider: :anthropic, model: "claude-sonnet-4-20250514" },
    "openai" => { provider: :open_ai, model: "gpt-4o" },
    "ollama" => { provider: :ollama, model: "llama3.1:8b" }
  }.freeze

  # Queue for async processing
  self.generate_later_queue_name = :sandboxes

  # Define the action for asking questions
  def ask
    config = PROVIDER_CONFIGS[params[:provider]] || PROVIDER_CONFIGS["anthropic"]

    # Dynamically set the provider for this request
    self.class.generate_with config[:provider], model: config[:model]

    prompt(
      instructions: default_instructions,
      message: params[:task],
      max_tokens: 1024,
      temperature: 0.7
    )
  end

  # Callback after generation completes - record the result
  after_generation :record_sandbox_run

  private

  def record_sandbox_run
    return unless params[:sandbox_session_id].present?

    sandbox = SandboxSession.find(params[:sandbox_session_id])
    return unless sandbox

    # Extract result from the response
    content = response&.message&.content || "No response generated"
    tokens = (response&.usage&.[](:input_tokens) || 0) + (response&.usage&.[](:output_tokens) || 0)

    # Record the run with thread-safe locking
    run = sandbox.record_run!(
      task: params[:task],
      result: content,
      duration_ms: params[:duration_ms] || 0,
      tokens: tokens,
      screenshots: [],
      provider: params[:provider]
    )

    # Update sandbox status
    sandbox.update!(status: :ready)

    # Broadcast completion via ActionCable
    ActionCable.server.broadcast(
      "sandbox_#{sandbox.session_id}",
      {
        type: "run_complete",
        run_id: params[:run_id],
        run: run,
        sandbox: sandbox.summary
      }
    )
  rescue => e
    Rails.logger.error("Failed to record sandbox run: #{e.message}")

    if params[:sandbox_session_id].present?
      sandbox = SandboxSession.find_by(id: params[:sandbox_session_id])
      if sandbox
        sandbox.update!(status: :ready, error_message: e.message)

        ActionCable.server.broadcast(
          "sandbox_#{sandbox.session_id}",
          {
            type: "run_error",
            run_id: params[:run_id],
            error: e.message,
            sandbox: sandbox.summary
          }
        )
      end
    end
  end
end
