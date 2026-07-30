# frozen_string_literal: true

module Api
  module Sandbox
    class RunsController < BaseController
      # GET /api/sandbox/status
      # Returns sandbox status and capabilities
      def status
        render json: {
          session_id: sandbox_session_id,
          sandbox_mode: true,
          limits: sandbox_limits,
          runs_count: SandboxRun.count,
          runs_remaining: sandbox_limits[:max_runs] - SandboxRun.count,
          capabilities: available_capabilities,
          started_at: Rails.application.config.sandbox_started_at,
          uptime_seconds: (Time.current - Rails.application.config.sandbox_started_at).to_i
        }
      end

      # GET /api/sandbox/runs
      # Returns run history
      def index
        runs = SandboxRun.order(created_at: :desc).limit(20)
        render json: { runs: runs.map(&:summary) }
      end

      # POST /api/sandbox/run
      # Execute a task using the available agent capabilities
      def create
        # Check run limits
        if SandboxRun.count >= sandbox_limits[:max_runs]
          return render json: {
            error: "Maximum runs exceeded",
            runs_count: SandboxRun.count,
            max_runs: sandbox_limits[:max_runs]
          }, status: :unprocessable_entity
        end

        task = params[:task]
        return render json: { error: "Task required" }, status: :bad_request unless task.present?

        # Create run record
        run = SandboxRun.create!(
          task: task,
          status: :running,
          started_at: Time.current
        )

        # Execute the agent task
        begin
          result = execute_agent_task(task, run)

          run.update!(
            status: :completed,
            result: result[:output],
            screenshots: result[:screenshots] || [],
            tokens_used: result[:tokens] || 0,
            completed_at: Time.current,
            duration_ms: ((Time.current - run.started_at) * 1000).to_i
          )

          render json: {
            run: run.summary,
            output: result[:output],
            screenshots: result[:screenshots]
          }
        rescue StandardError => e
          run.update!(
            status: :failed,
            error: e.message,
            completed_at: Time.current
          )

          render json: {
            run: run.summary,
            error: e.message
          }, status: :unprocessable_entity
        end
      end

      # GET /api/sandbox/runs/:id
      def show
        run = SandboxRun.find(params[:id])
        render json: { run: run.details }
      end

      private

      def available_capabilities
        capabilities = []

        # Check for Playwright MCP
        if playwright_available?
          capabilities << {
            type: "playwright_mcp",
            name: "Browser Automation",
            description: "Navigate, screenshot, and interact with web pages"
          }
        end

        # Check for terminal access
        if terminal_available?
          capabilities << {
            type: "terminal",
            name: "Terminal",
            description: "Execute system commands"
          }
        end

        capabilities
      end

      def playwright_available?
        # Check if Playwright MCP server is available
        system("which npx > /dev/null 2>&1") &&
          File.exist?("/usr/local/bin/node") ||
          system("npx @anthropic/mcp-server-playwright --help > /dev/null 2>&1")
      end

      def terminal_available?
        true # Terminal is always available in sandbox
      end

      def execute_agent_task(task, run)
        # Use ActiveAgent to execute the task with available tools
        agent = build_sandbox_agent

        # Set timeout
        Timeout.timeout(sandbox_limits[:timeout_seconds]) do
          result = agent.execute(task)

          {
            output: result.response,
            screenshots: extract_screenshots(result),
            tokens: result.usage&.total_tokens || 0
          }
        end
      rescue Timeout::Error
        raise "Task timed out after #{sandbox_limits[:timeout_seconds]} seconds"
      end

      def build_sandbox_agent
        # Build an agent with sandbox-appropriate tools
        tools = []

        if playwright_available?
          tools << PlaywrightMcpTool.new
        end

        if terminal_available?
          tools << RestrictedTerminalTool.new
        end

        ActiveAgent::Agent.new(
          model: "claude-haiku-4-5",
          tools: tools,
          max_tokens: [ sandbox_limits[:max_tokens], 10_000 ].min,
          system_prompt: sandbox_system_prompt
        )
      end

      def sandbox_system_prompt
        <<~PROMPT
          You are running in a sandbox environment with limited capabilities.
          This is a demonstration of ActiveAgents platform capabilities.

          Available tools:
          - Browser automation via Playwright MCP (navigate, screenshot, interact)
          - Restricted terminal access (safe commands only)

          Be concise and focus on completing the user's task efficiently.
          Always explain what you're doing step by step.
        PROMPT
      end

      def extract_screenshots(result)
        # Extract any screenshot artifacts from the agent result
        result.artifacts&.select { |a| a[:type] == "screenshot" } || []
      end
    end
  end
end
