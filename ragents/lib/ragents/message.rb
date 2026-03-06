# frozen_string_literal: true

module Ragents
  # Message is the fundamental unit of communication between Ractors.
  #
  # All Message subclasses are defined with Data.define, making them:
  #   - Immutable (frozen by default in Ruby 4)
  #   - Shareable across Ractor boundaries without copying
  #   - Structurally typed
  #
  # The message hierarchy mirrors the roles in a conversation:
  #
  #   UserMessage    — input from a caller / human
  #   AssistantMessage — LLM response text
  #   SystemMessage  — system prompt / instructions
  #   ToolCallMessage — LLM requests a tool to be invoked
  #   ToolResultMessage — result of a tool invocation sent back to the LLM
  #   AgentCallMessage — request to invoke another agent (agent-as-a-tool)
  #   AgentResultMessage — response from a sub-agent
  #   ErrorMessage   — propagate failures across Ractor boundaries
  #
  # Because these are Data structs they can be sent via Ractor#send and
  # Ractor.yield without marshalling — the Ractor VM moves the reference
  # directly when the object is frozen/shareable.

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Validate that the role is one of the supported values.
  ROLES = %i[system user assistant tool].freeze

  # ---------------------------------------------------------------------------
  # Base behaviour mixed into every message struct
  # ---------------------------------------------------------------------------
  module MessageBase
    def validate!
      # Subclasses override to add constraints
    end

    def to_h
      super.transform_values do |v|
        v.respond_to?(:to_h) ? v.to_h : v
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Core message types
  # ---------------------------------------------------------------------------

  # A text message from the user / caller.
  UserMessage = Data.define(:content, :name) do
    include MessageBase

    # Ruby 4.0: override initialize instead of self.new
    def initialize(content:, name: nil)
      super(content: content.to_s, name: name&.to_s)
    end

    def role = :user
  end

  # A text response produced by the LLM.
  AssistantMessage = Data.define(:content, :input_tokens, :output_tokens, :model) do
    include MessageBase

    # Ruby 4.0: override initialize instead of self.new
    def initialize(content:, input_tokens: nil, output_tokens: nil, model: nil)
      super(content: content.to_s, input_tokens: input_tokens, output_tokens: output_tokens, model: model&.to_s)
    end

    def role = :assistant
  end

  # A system-level instruction that scopes the agent's behaviour.
  SystemMessage = Data.define(:content) do
    include MessageBase

    # Ruby 4.0: override initialize instead of self.new
    def initialize(content:)
      super(content: content.to_s)
    end

    def role = :system
  end

  # The LLM has decided to call a tool.  The agent supervisor routes this to
  # the appropriate Ractor or method and sends back a ToolResultMessage.
  ToolCallMessage = Data.define(:tool_call_id, :name, :arguments) do
    include MessageBase

    # Ruby 4.0: override initialize instead of self.new
    def initialize(tool_call_id:, name:, arguments: {})
      super(
        tool_call_id: tool_call_id.to_s,
        name: name.to_s,
        # arguments must be a plain Hash of shareable primitives
        arguments: self.class.deep_freeze_hash(arguments)
      )
    end

    def role = :assistant

    def self.deep_freeze_hash(h)
      h.transform_keys(&:to_sym).transform_values do |v|
        case v
        when Hash   then deep_freeze_hash(v)
        when Array  then v.map { |e| e.is_a?(Hash) ? deep_freeze_hash(e) : e.dup.freeze }.freeze
        when String then v.dup.freeze
        else v
        end
      end.freeze
    end
  end

  # The result of executing a tool, sent back into the conversation context.
  ToolResultMessage = Data.define(:tool_call_id, :name, :content, :error) do
    include MessageBase

    # Ruby 4.0: override initialize instead of self.new
    def initialize(tool_call_id:, name:, content: nil, error: nil)
      super(
        tool_call_id: tool_call_id.to_s,
        name: name.to_s,
        content: content.nil? ? nil : content.to_s,
        error: error.nil? ? nil : error.to_s
      )
    end

    def role = :tool
    def success? = error.nil?
  end

  # Caller requests that a named sub-agent be invoked (agent-as-a-tool).
  # The supervisor resolves the agent by name and sends back an AgentResultMessage.
  AgentCallMessage = Data.define(:call_id, :agent_name, :input, :context_id) do
    include MessageBase

    # Ruby 4.0: override initialize instead of self.new
    def initialize(call_id:, agent_name:, input:, context_id: nil)
      super(
        call_id: call_id.to_s,
        agent_name: agent_name.to_s,
        input: input.to_s,
        context_id: context_id&.to_s
      )
    end
  end

  # Result from an invoked sub-agent.
  AgentResultMessage = Data.define(:call_id, :agent_name, :output, :error) do
    include MessageBase

    # Ruby 4.0: override initialize instead of self.new
    def initialize(call_id:, agent_name:, output: nil, error: nil)
      super(
        call_id: call_id.to_s,
        agent_name: agent_name.to_s,
        output: output.nil? ? nil : output.to_s,
        error: error.nil? ? nil : error.to_s
      )
    end

    def success? = error.nil?
  end

  # Wraps any Ruby exception for cross-Ractor propagation.
  # The original exception cannot cross Ractor boundaries, so we capture the
  # message, class name, and backtrace as frozen strings.
  ErrorMessage = Data.define(:source, :exception_class, :message, :backtrace) do
    include MessageBase

    def self.from_exception(source:, exception:)
      new(
        source: source.to_s,
        exception_class: exception.class.name.freeze,
        message: exception.message.dup.freeze,
        backtrace: (exception.backtrace || []).map(&:dup).map(&:freeze).freeze
      )
    end

    def to_exception
      # Re-hydrate as a generic RuntimeError with preserved context
      RuntimeError.new("#{exception_class}: #{message}")
    end
  end
end
