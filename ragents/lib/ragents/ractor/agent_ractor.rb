# frozen_string_literal: true

module Ragents
  module Ractor
    # AgentRactor wraps an agent's execution loop inside a Ruby Ractor,
    # enabling true parallel execution across CPU cores.
    #
    # ## Why Ractors for LLM agents?
    #
    # LLM calls are I/O-bound (seconds of network wait) and naturally parallel.
    # Ruby Threads share the GVL, meaning only one thread runs Ruby code at a
    # time — though I/O blocking does release the GVL.  Ractors have their own
    # GVL per Ractor, so N Ractors can execute N pieces of Ruby *and* I/O work
    # truly in parallel on N CPU cores.
    #
    # For agent workloads the gains are twofold:
    #   1. Response parsing, token counting, context building — real CPU work —
    #      runs in parallel across Ractors.
    #   2. Ractor isolation prevents accidental shared state bugs that are
    #      common in multi-threaded agent systems.
    #
    # ## Object Passing and Context Management
    #
    # Ractors cannot share mutable objects.  Instead, they communicate via
    # *message passing* using Ractor#send / Ractor.receive.
    #
    # Ragents leverages this constraint to build a clean context management model:
    #
    #   - All messages (UserMessage, AssistantMessage, ToolCallMessage, …) are
    #     `Data.define` structs — immutable and therefore shareable by reference
    #     without copying.
    #   - Context snapshots (frozen Array<Message>) can be passed to child
    #     Ractors when spawning sub-agents.
    #   - Tool results are wrapped in ToolResultMessage and sent back via the
    #     Ractor's inbox.
    #
    # ## Protocol
    #
    # The Ractor processes a single *request* per run:
    #
    #   1. Caller creates an AgentRactor with provider + tools configuration.
    #   2. Caller calls #run(user_input, context_snapshot: nil) which:
    #      a. Spawns a Ractor
    #      b. Sends a StartMessage into the Ractor's inbox
    #      c. Enters a loop: receives messages, dispatches tool calls,
    #         sends results back, until a FinalMessage arrives.
    #   3. Returns the final AssistantMessage.
    #
    # The spawned Ractor never reaches out to the outside world for tools —
    # all tool calls are sent back to the *caller* Ractor (supervisor) which
    # executes them and returns results.  This keeps I/O concerns outside the
    # Ractor and makes tools easy to test.

    # Internal message types for the Ractor protocol (not part of public API)
    StartMessage = Data.define(:user_input, :context_snapshot, :system_prompt, :tool_schemas, :max_iterations)
    ToolRequestMessage  = Data.define(:tool_calls)   # Ractor → supervisor
    ToolResultsMessage  = Data.define(:results)       # supervisor → Ractor
    FinalMessage        = Data.define(:assistant_message, :context_snapshot)
    FailureMessage      = Data.define(:error_message)

    class AgentRactor
      # @param provider_class [Class] a BaseProvider subclass
      # @param provider_opts  [Hash]  options forwarded to provider constructor
      # @param tools          [Array<Tool>] frozen Tool objects
      # @param system_prompt  [String, nil]
      # @param model          [String, nil]
      # @param max_iterations [Integer] guard against infinite tool loops
      def initialize(
        provider_class:,
        provider_opts: {},
        tools: [],
        system_prompt: nil,
        model: nil,
        max_iterations: 10
      )
        @provider_class  = provider_class
        @provider_opts   = provider_opts.freeze
        @tools           = tools.map { |t| t.frozen? ? t : t.dup.freeze }
        @system_prompt   = system_prompt&.dup&.freeze
        @model           = model&.dup&.freeze
        @max_iterations  = max_iterations
        freeze
      end

      # Run an agent turn synchronously, returning AssistantMessage.
      #
      # All tool execution happens in the calling Ractor (supervisor role),
      # while the LLM interaction happens in a spawned Ractor.
      #
      # @param user_input [String] the user's message
      # @param context_snapshot [Array<Message>, nil] prior conversation history
      # @param tool_registry [ToolRegistry, nil] tool executor; uses @tools if nil
      # @return [RunResult]
      def run(user_input, context_snapshot: nil, tool_registry: nil)
        tool_reg = tool_registry || ToolRegistry.new(@tools)

        # Capture all values needed inside the Ractor before spawning.
        # Everything passed must be shareable (frozen).
        provider_class  = @provider_class
        provider_opts   = @provider_opts
        tools           = @tools
        system_prompt   = @system_prompt
        model           = @model
        max_iterations  = @max_iterations

        caller_ractor = ::Ractor.current

        worker = ::Ractor.new(
          caller_ractor, user_input, context_snapshot,
          provider_class, provider_opts, tools, system_prompt, model, max_iterations
        ) do |supervisor, input, ctx_snap, prov_cls, prov_opts, tool_list, sys_prompt, mdl, max_iter|
          AgentWorker.new(
            supervisor: supervisor,
            provider: prov_cls.new(**prov_opts),
            tools: tool_list,
            system_prompt: sys_prompt,
            model: mdl,
            max_iterations: max_iter
          ).run(input, ctx_snap)
        end

        # Supervisor loop: dispatch tool requests from the worker
        loop do
          message = worker.take

          case message
          when ToolRequestMessage
            # Execute tool calls in the supervisor's context (this Ractor)
            results = message.tool_calls.map do |tc|
              execute_tool_call(tc, tool_reg)
            end
            worker.send(ToolResultsMessage.new(results: results.freeze))

          when FinalMessage
            return RunResult.new(
              assistant_message: message.assistant_message,
              context_snapshot: message.context_snapshot
            )

          when FailureMessage
            raise message.error_message.to_exception

          else
            raise Error, "Unexpected message from worker Ractor: #{message.class}"
          end
        end
      ensure
        # Ensure the worker Ractor is collected even on exception
        worker&.close_outgoing rescue nil
      end

      # Run multiple inputs concurrently, each in its own Ractor.
      # Returns an Array<RunResult> in the same order as inputs.
      #
      # @param inputs [Array<String>]
      # @param context_snapshot [Array<Message>, nil] shared starting context
      # @return [Array<RunResult>]
      def run_parallel(inputs, context_snapshot: nil)
        # Each input gets its own supervisor + worker pair.
        # We spin up threads to supervise each worker pair so that multiple
        # supervisor loops can run concurrently.
        threads = inputs.map do |input|
          Thread.new { run(input, context_snapshot: context_snapshot) }
        end

        threads.map(&:value)
      end

      private

      def execute_tool_call(tc, tool_registry)
        if tool_registry.include?(tc.name)
          result = tool_registry.execute(tc.name, **tc.arguments)
          ToolResultMessage.new(tool_call_id: tc.id, name: tc.name, content: result)
        else
          ToolResultMessage.new(tool_call_id: tc.id, name: tc.name, error: "Unknown tool: #{tc.name}")
        end
      rescue StandardError => e
        ToolResultMessage.new(tool_call_id: tc.id, name: tc.name, error: e.message)
      end
    end

    # ---------------------------------------------------------------------------
    # AgentWorker — runs inside the spawned Ractor
    # ---------------------------------------------------------------------------

    # AgentWorker is instantiated *inside* the Ractor and therefore does NOT
    # need to be shareable.  It may hold mutable state (Context, call_count).
    class AgentWorker
      MAX_ITERATIONS_DEFAULT = 10

      def initialize(supervisor:, provider:, tools:, system_prompt:, model:, max_iterations:)
        @supervisor     = supervisor
        @provider       = provider
        @tool_schemas   = tools.map(&:to_schema)
        @system_prompt  = system_prompt
        @model          = model
        @max_iterations = max_iterations || MAX_ITERATIONS_DEFAULT
      end

      def run(user_input, context_snapshot)
        @context = if context_snapshot&.any?
                     ::Ragents::Context.import(context_snapshot, agent_id: "worker")
                   else
                     ::Ragents::Context.new(agent_id: "worker")
                   end

        @context.add(::Ragents::SystemMessage.new(content: @system_prompt)) if @system_prompt && @context.system_messages.empty?
        @context.add(::Ragents::UserMessage.new(content: user_input))

        iterations = 0

        loop do
          iterations += 1
          if iterations > @max_iterations
            yield_failure("Max iterations (#{@max_iterations}) exceeded without a final response")
            return
          end

          result = @provider.chat(
            messages: @context.to_api_messages,
            tools: @tool_schemas,
            model: @model
          )

          if result.tool_call?
            handle_tool_calls(result)
          else
            # Final response — yield result back to supervisor
            assistant_msg = ::Ragents::AssistantMessage.new(
              content: result.content || "",
              input_tokens: result.input_tokens,
              output_tokens: result.output_tokens,
              model: result.model
            )
            @context.add(assistant_msg)

            ::Ractor.yield(
              FinalMessage.new(
                assistant_message: assistant_msg,
                context_snapshot: @context.snapshot
              )
            )
            return
          end
        end
      rescue StandardError => e
        ::Ractor.yield(
          FailureMessage.new(
            error_message: ::Ragents::ErrorMessage.from_exception(source: "AgentWorker", exception: e)
          )
        )
      end

      private

      def handle_tool_calls(result)
        # Record the LLM's tool-call decision in context
        result.tool_calls.each do |tc|
          @context.add(tc.to_tool_call_message)
        end

        # Ask supervisor to execute the tools
        ::Ractor.yield(ToolRequestMessage.new(tool_calls: result.tool_calls.freeze))

        # Wait for results
        results_msg = ::Ractor.receive
        results_msg.results.each { |r| @context.add(r) }
      end

      def yield_failure(message)
        ::Ractor.yield(
          FailureMessage.new(
            error_message: ::Ragents::ErrorMessage.new(
              source: "AgentWorker",
              exception_class: "Ragents::MaxIterationsError",
              message: message,
              backtrace: []
            )
          )
        )
      end
    end

    # Value object returned by AgentRactor#run
    RunResult = Data.define(:assistant_message, :context_snapshot) do
      def content = assistant_message.content
      def messages = context_snapshot
    end
  end
end
