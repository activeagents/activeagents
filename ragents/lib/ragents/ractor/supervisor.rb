# frozen_string_literal: true

module Ragents
  module Ractor
    # Supervisor coordinates a graph of agents where agents can call other
    # agents as tools (agent-as-a-tool pattern).
    #
    # ## Agent-as-a-Tool
    #
    # One agent can delegate work to another agent by declaring a tool whose
    # `execute` method spawns a child AgentRactor.  The child agent runs in
    # its own Ractor, uses its own provider, and returns an AssistantMessage.
    # The parent agent receives this as a ToolResultMessage and continues its
    # own reasoning loop.
    #
    # This enables powerful compositional patterns:
    #
    #   orchestrator_agent calls:
    #     ├── research_agent (via AgentTool)   → runs in Ractor A
    #     ├── coder_agent    (via AgentTool)   → runs in Ractor B
    #     └── critic_agent   (via AgentTool)   → runs in Ractor C
    #
    # Because each child agent runs in its own Ractor, all three can execute
    # truly in parallel when the orchestrator issues multiple tool calls.
    #
    # ## Context Propagation
    #
    # The parent's context snapshot (a frozen Array<Message>) is optionally
    # forwarded to child agents, giving them awareness of the conversation
    # history.  Child agents build their own Context from that snapshot and
    # add their own turns without affecting the parent's mutable Context.
    #
    # ## MCP (Model Context Protocol) Integration
    #
    # MCP servers expose capabilities as tools.  In Ragents, an MCP tool is
    # just another Tool whose #execute method communicates with the MCP server
    # over HTTP/stdio.  Because MCP calls are I/O-bound, they benefit from the
    # same Ractor-per-agent isolation — each agent's MCP calls run in parallel
    # without GVL contention.
    #
    # See McpTool for a reference implementation.

    class Supervisor
      attr_reader :agents

      def initialize
        @agents = {}
        @agent_tools = {}
      end

      # Register an agent by name.
      # The agent config Hash will be used to construct an AgentRactor on demand.
      #
      # @param name [String, Symbol]
      # @param provider_class [Class]
      # @param provider_opts [Hash]
      # @param tools [Array<Tool>]
      # @param system_prompt [String, nil]
      # @param model [String, nil]
      # @param max_iterations [Integer]
      def register(name, provider_class:, provider_opts: {}, tools: [], system_prompt: nil, model: nil, max_iterations: 10)
        key = name.to_s.freeze
        @agents[key] = {
          provider_class: provider_class,
          provider_opts: provider_opts.freeze,
          tools: tools,
          system_prompt: system_prompt&.freeze,
          model: model&.freeze,
          max_iterations: max_iterations
        }.freeze
        self
      end

      # Build an AgentTool that lets one agent call another by name.
      # The returned Tool object can be passed to any AgentRactor's `tools:` list.
      #
      # @param agent_name [String] name of the registered agent
      # @param description [String] what this agent does, shown to the LLM
      # @param input_description [String] description of the input parameter
      # @return [Tool]
      def agent_tool(agent_name, description:, input_description: "The task or question for this agent")
        name = agent_name.to_s

        raise KeyError, "Agent '#{name}' is not registered" unless @agents.key?(name)

        config = @agents[name]

        Tool.new(
          name: "call_#{name}_agent",
          description: description,
          parameters: {
            type: "object",
            properties: {
              input: {
                type: "string",
                description: input_description
              },
              forward_context: {
                type: "boolean",
                description: "Whether to pass the current conversation context to this agent"
              }
            },
            required: ["input"]
          }
        ) do |input:, forward_context: false, context_snapshot: nil|
          agent_ractor = AgentRactor.new(
            provider_class: config[:provider_class],
            provider_opts: config[:provider_opts],
            tools: config[:tools],
            system_prompt: config[:system_prompt],
            model: config[:model],
            max_iterations: config[:max_iterations]
          )

          snap = forward_context ? context_snapshot : nil
          result = agent_ractor.run(input, context_snapshot: snap)
          result.content
        end
      end

      # Run a named agent directly.
      #
      # @param name [String, Symbol]
      # @param user_input [String]
      # @param context_snapshot [Array<Message>, nil]
      # @return [RunResult]
      def run(name, user_input, context_snapshot: nil)
        config = @agents.fetch(name.to_s) { raise KeyError, "Agent '#{name}' not registered" }

        AgentRactor.new(
          provider_class: config[:provider_class],
          provider_opts: config[:provider_opts],
          tools: config[:tools],
          system_prompt: config[:system_prompt],
          model: config[:model],
          max_iterations: config[:max_iterations]
        ).run(user_input, context_snapshot: context_snapshot)
      end

      # Run multiple named agents in parallel, each with its own input.
      # Returns Hash<agent_name => RunResult>.
      #
      # @param tasks [Hash<String => String>] { agent_name => user_input }
      # @param context_snapshot [Array<Message>, nil]
      # @return [Hash<String => RunResult>]
      def run_parallel(tasks, context_snapshot: nil)
        threads = tasks.map do |agent_name, user_input|
          [agent_name.to_s, Thread.new { run(agent_name, user_input, context_snapshot: context_snapshot) }]
        end

        threads.to_h { |name, t| [name, t.value] }
      end
    end
  end
end
