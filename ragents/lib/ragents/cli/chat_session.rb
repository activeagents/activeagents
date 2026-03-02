# frozen_string_literal: true

require "json"
require "time"

module Ragents
  module CLI
    # ChatSession — the brains of the TUI.
    #
    # Owns:
    #   - The conversation display model (display_messages)
    #   - The Ractor agent lifecycle (one AgentRactor per turn)
    #   - Context snapshot (passed between turns for continuity)
    #   - Built-in slash command handling
    #   - Tool definitions registered for this session
    #   - Parallel run mode (/parallel)
    #
    # ChatSession is deliberately separate from TUI (rendering) and InputHandler
    # (key events) so it can be tested independently and used headlessly.

    class ChatSession
      attr_reader :display_messages, :provider_name, :model_name,
                  :tool_count, :total_tokens, :message_count,
                  :system_prompt, :max_iterations

      def initialize(
        provider_class:,
        provider_opts: {},
        system_prompt: nil,
        model: nil,
        tools: [],
        max_iterations: 10
      )
        @provider_class  = provider_class
        @provider_opts   = provider_opts
        @system_prompt   = system_prompt
        @model           = model
        @tools           = tools
        @max_iterations  = max_iterations

        @context_snapshot = nil
        @display_messages = []
        @total_tokens     = 0
        @message_count    = 0
        @thinking         = false
        @cancelled        = false

        # Derive display metadata
        @provider_name = provider_class.name.split("::").last.sub("Provider", "")
        @model_name    = model
        @tool_count    = tools.size

        # Seed display with system prompt if present
        if system_prompt
          @display_messages << { type: :system, content: system_prompt }
        end
      end

      def thinking?  = @thinking
      def cancelled? = @cancelled

      # ── Submit a message or slash command ────────────────────────────────────

      # Returns :ok, :quit, :clear, or :error
      def submit(input)
        text = input.strip
        return :ok if text.empty?

        if text.start_with?("/")
          handle_command(text)
        else
          run_agent_turn(text)
        end
      end

      # ── Slash commands ────────────────────────────────────────────────────────

      COMMANDS = {
        "/help"     => "Show available commands",
        "/tools"    => "List registered tools",
        "/context"  => "Show full conversation context JSON",
        "/clear"    => "Start a new conversation (resets context)",
        "/parallel" => "Run multiple prompts in parallel  e.g. /parallel Q1 | Q2 | Q3",
        "/model"    => "Switch model  e.g. /model gpt-4o",
        "/system"   => "Set system prompt  e.g. /system You are a pirate",
        "/export"   => "Export conversation to JSON",
        "/quit"     => "Exit ragents"
      }.freeze

      # ── Public accessors for TUI ──────────────────────────────────────────────

      def cancel!
        @cancelled = true
      end

      private

      # ── Agent execution ───────────────────────────────────────────────────────

      def run_agent_turn(text)
        @display_messages << { type: :user, content: text }
        @message_count    += 1
        @thinking          = true
        @cancelled         = false

        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)

        begin
          agent = Ragents::Ractor::AgentRactor.new(
            provider_class: @provider_class,
            provider_opts:  @provider_opts,
            tools:          @tools,
            system_prompt:  effective_system_prompt,
            model:          @model,
            max_iterations: @max_iterations
          )

          # Run in a thread so we can return control to the spinner/event loop
          result_box = { result: nil, error: nil }
          agent_thread = Thread.new do
            result_box[:result] = agent.run(text, context_snapshot: @context_snapshot)
          rescue => e
            result_box[:error] = e
          end

          # Wait, polling for cancellation
          agent_thread.join(0.1) until !agent_thread.alive? || @cancelled

          if @cancelled
            agent_thread.kill rescue nil
            @display_messages << { type: :error, content: "Cancelled." }
            return :ok
          end

          if (err = result_box[:error])
            @display_messages << { type: :error, content: err.message }
            return :error
          end

          result = result_box[:result]
          duration_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - started_at

          # Absorb the full context — includes tool calls + results automatically
          @context_snapshot = result.context_snapshot
          @model_name     ||= result.assistant_message.model

          # Append tool call / result entries from the new context
          append_tool_messages(result.context_snapshot)

          # Append the assistant reply
          am = result.assistant_message
          @total_tokens  += (am.input_tokens || 0) + (am.output_tokens || 0)
          @message_count += 1

          @display_messages << {
            type:          :assistant,
            content:       am.content,
            input_tokens:  am.input_tokens,
            output_tokens: am.output_tokens,
            model:         am.model,
            duration_ms:   duration_ms
          }
        rescue Interrupt
          @display_messages << { type: :error, content: "Interrupted." }
        ensure
          @thinking = false
        end

        :ok
      end

      # Walk the latest context snapshot and append any tool call/result pairs
      # that are not yet in display_messages.
      def append_tool_messages(snapshot)
        already_shown_ids = @display_messages
                            .select { |m| m[:type] == :tool_call }
                            .map { |m| m[:tool_call_id] }
                            .to_set

        snapshot.each do |msg|
          case msg
          when Ragents::ToolCallMessage
            next if already_shown_ids.include?(msg.tool_call_id)

            @display_messages << {
              type:         :tool_call,
              tool_call_id: msg.tool_call_id,
              name:         msg.name,
              arguments:    msg.arguments
            }
          when Ragents::ToolResultMessage
            next if already_shown_ids.include?(msg.tool_call_id)

            @display_messages << {
              type:         :tool_result,
              tool_call_id: msg.tool_call_id,
              name:         msg.name,
              content:      msg.content,
              error:        msg.error
            }
          end
        end
      end

      # ── Slash command handlers ─────────────────────────────────────────────

      def handle_command(text)
        cmd, *rest = text.split(" ", 2)
        arg = rest.first&.strip

        case cmd
        when "/help"
          lines = COMMANDS.map { |c, d| "  #{c.ljust(12)} #{d}" }.join("\n")
          @display_messages << { type: :system, content: "Commands:\n#{lines}" }

        when "/tools"
          if @tools.empty?
            @display_messages << { type: :system, content: "No tools registered. Use --tool flag or add via API." }
          else
            lines = @tools.map { |t| "  #{t.name.ljust(20)} #{t.description}" }.join("\n")
            @display_messages << { type: :system, content: "Registered tools:\n#{lines}" }
          end

        when "/context"
          if @context_snapshot.nil?
            @display_messages << { type: :system, content: "No context yet — send a message first." }
          else
            api_messages = build_context_display
            @display_messages << { type: :system, content: api_messages }
          end

        when "/clear"
          @context_snapshot = nil
          @display_messages.clear
          @total_tokens  = 0
          @message_count = 0
          @display_messages << { type: :system, content: @system_prompt } if @system_prompt
          return :clear

        when "/parallel"
          run_parallel_prompts(arg)

        when "/model"
          if arg.nil? || arg.empty?
            @display_messages << { type: :system, content: "Current model: #{@model_name || "provider default"}" }
          else
            @model      = arg
            @model_name = arg
            @display_messages << { type: :system, content: "Model switched to: #{arg}" }
          end

        when "/system"
          if arg.nil? || arg.empty?
            @display_messages << { type: :system, content: "Current system prompt:\n  #{@system_prompt || "(none)"}" }
          else
            @system_prompt = arg
            @context_snapshot = nil  # reset context so new system prompt takes effect
            @display_messages << { type: :system, content: "System prompt updated. Context reset." }
          end

        when "/export"
          export_conversation(arg)

        when "/quit", "/exit", "/q"
          return :quit

        else
          @display_messages << { type: :error, content: "Unknown command: #{cmd}. Type /help for a list." }
        end

        :ok
      end

      def run_parallel_prompts(arg)
        if arg.nil? || arg.empty?
          @display_messages << { type: :error, content: "Usage: /parallel Q1 | Q2 | Q3" }
          return
        end

        prompts = arg.split("|").map(&:strip).reject(&:empty?)
        if prompts.length < 2
          @display_messages << { type: :error, content: "Provide at least 2 prompts separated by |" }
          return
        end

        @display_messages << {
          type: :system,
          content: "Running #{prompts.length} prompts in parallel via Ractor pool…"
        }
        @thinking = true

        begin
          pool = Ragents::Ractor::AgentPool.new(
            size:           [prompts.length, 8].min,
            provider_class: @provider_class,
            provider_opts:  @provider_opts,
            system_prompt:  effective_system_prompt,
            model:          @model,
            max_iterations: @max_iterations
          )

          results = []
          pool_thread = Thread.new { results = pool.process(prompts, context_snapshot: @context_snapshot) }
          pool_thread.join(0.1) until !pool_thread.alive? || @cancelled

          if @cancelled
            pool_thread.kill rescue nil
            @display_messages << { type: :error, content: "Parallel run cancelled." }
            return
          end

          prompts.each_with_index do |prompt, i|
            r = results[i]
            @display_messages << { type: :user, content: "(#{i + 1}/#{prompts.length}) #{prompt}" }
            if r.respond_to?(:success?) && !r.success?
              @display_messages << { type: :error, content: r.content }
            else
              @display_messages << {
                type:    :assistant,
                content: r.content,
                model:   r.assistant_message&.model
              }
            end
          end
        rescue => e
          @display_messages << { type: :error, content: "Parallel error: #{e.message}" }
        ensure
          @thinking = false
        end
      end

      def export_conversation(path)
        path ||= "ragents_export_#{Time.now.strftime("%Y%m%d_%H%M%S")}.json"
        data = {
          exported_at:    Time.now.iso8601,
          provider:       @provider_name,
          model:          @model_name,
          system_prompt:  @system_prompt,
          total_tokens:   @total_tokens,
          messages:       @display_messages
        }
        File.write(path, JSON.pretty_generate(data))
        @display_messages << { type: :system, content: "Conversation exported to: #{path}" }
      rescue => e
        @display_messages << { type: :error, content: "Export failed: #{e.message}" }
      end

      def build_context_display
        return "" unless @context_snapshot

        @context_snapshot.map do |m|
          "#{m.role}: #{m.respond_to?(:content) ? m.content.to_s[0, 100] : m.inspect}"
        end.join("\n")
      end

      def effective_system_prompt
        @system_prompt
      end
    end
  end
end
