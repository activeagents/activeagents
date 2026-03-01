# frozen_string_literal: true

class SandboxRunJob < ApplicationJob
  queue_as :sandboxes

  # Execute a task in the sandbox
  def perform(sandbox_session_id, run_id, task)
    sandbox = SandboxSession.find(sandbox_session_id)
    return unless sandbox.can_run?

    started_at = Time.current

    begin
      # Execute the task based on sandbox type
      result = case sandbox.sandbox_type
      when "playwright_mcp"
        execute_playwright_task(sandbox, task)
      when "terminal"
        execute_terminal_task(sandbox, task)
      when "research"
        execute_research_task(sandbox, task)
      else
        { content: "Unknown sandbox type", tokens: 0 }
      end

      duration_ms = ((Time.current - started_at) * 1000).to_i

      # Record the run
      run = sandbox.record_run!(
        task: task,
        result: result[:content],
        duration_ms: duration_ms,
        tokens: result[:tokens] || 0,
        screenshots: result[:screenshots] || []
      )

      sandbox.update!(status: :ready)

      # Broadcast completion
      broadcast_run_complete(sandbox, run_id, run)
    rescue => e
      Rails.logger.error("Sandbox run failed: #{e.message}")
      sandbox.update!(status: :ready, error_message: e.message)
      broadcast_run_error(sandbox, run_id, e.message)
    end
  end

  private

  def execute_playwright_task(sandbox, task)
    # If we have a Cloud Run URL, call it
    if sandbox.cloud_run_url.present? && !sandbox.cloud_run_url.include?("localhost")
      execute_remote_task(sandbox.cloud_run_url, task)
    else
      execute_local_playwright_task(task)
    end
  end

  def execute_local_playwright_task(task)
    system_prompt = <<~PROMPT
      You are a browser automation assistant using Playwright MCP.

      Available actions:
      - browser_navigate: Go to a URL
      - browser_snapshot: Get the accessibility tree of current page
      - browser_click: Click on an element (use ref from snapshot)
      - browser_type: Type text into an input
      - browser_take_screenshot: Capture the current page
      - browser_wait_for: Wait for text or element

      Guidelines:
      1. Always take a snapshot first to understand the page structure
      2. Use element refs from snapshots for interactions
      3. Wait for page loads before taking actions
      4. Handle errors gracefully
      5. Describe what you would do step by step

      Note: In this demo environment, describe the actions you would take rather than executing them directly.
    PROMPT

    # Use ActiveAgent if available and properly configured, otherwise mock
    if defined?(ActiveAgent::Base) && ENV["ANTHROPIC_API_KEY"].present?
      begin
        execute_with_active_agent(system_prompt, task)
      rescue => e
        Rails.logger.warn("ActiveAgent execution failed, using mock: #{e.message}")
        execute_mock_task(task)
      end
    else
      execute_mock_task(task)
    end
  end

  def execute_with_active_agent(system_prompt, task)
    agent_class = Class.new(ActiveAgent::Base) do
      generate_with :anthropic, model: "claude-sonnet-4-20250514"

      define_method :perform do
        prompt instructions: system_prompt, message: task
      end
    end

    response = agent_class.perform.generate_now

    content = response.message&.content || "No response generated"
    tokens = (response.usage&.[](:input_tokens) || 0) + (response.usage&.[](:output_tokens) || 0)

    { content: content, tokens: tokens, screenshots: [] }
  end

  def execute_mock_task(task)
    # Mock response for development without ActiveAgent
    sleep(1)

    content = <<~RESPONSE
      Browser Automation Plan for: "#{task}"

      Step 1: Navigate to target URL
      - Use browser_navigate to go to the specified URL

      Step 2: Wait for page load
      - Use browser_wait_for to ensure page is fully loaded

      Step 3: Take snapshot
      - Use browser_snapshot to capture the accessibility tree

      Step 4: Take screenshot
      - Use browser_take_screenshot to capture visual state

      Note: This is a simulated response. In production, the agent would execute these actions using Playwright MCP.
    RESPONSE

    { content: content, tokens: task.split.size * 2 + 100, screenshots: [] }
  end

  def execute_terminal_task(sandbox, task)
    # Terminal sandbox implementation
    { content: "Terminal sandbox: #{task}", tokens: 0 }
  end

  def execute_research_task(sandbox, task)
    system_prompt = "You are a research assistant. Help the user research and summarize information."

    if defined?(ActiveAgent::Base)
      execute_with_active_agent(system_prompt, task)
    else
      { content: "Research response for: #{task}\n\nThis is a mock response.", tokens: 50 }
    end
  end

  def execute_remote_task(url, task)
    require "net/http"
    require "json"

    uri = URI("#{url}/run")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 300

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = { task: task }.to_json

    response = http.request(request)
    result = JSON.parse(response.body)

    {
      content: result["result"],
      tokens: result["tokens"] || 0,
      screenshots: result["screenshots"] || []
    }
  end

  def broadcast_run_complete(sandbox, run_id, run)
    ActionCable.server.broadcast(
      "sandbox_#{sandbox.session_id}",
      {
        type: "run_complete",
        run_id: run_id,
        run: run,
        sandbox: sandbox.summary
      }
    )
  end

  def broadcast_run_error(sandbox, run_id, error)
    ActionCable.server.broadcast(
      "sandbox_#{sandbox.session_id}",
      {
        type: "run_error",
        run_id: run_id,
        error: error,
        sandbox: sandbox.summary
      }
    )
  end
end
