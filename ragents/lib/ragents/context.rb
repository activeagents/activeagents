# frozen_string_literal: true

require "securerandom"
require "json"

module Ragents
  # Context manages the conversation history for a single agent interaction.
  #
  # ## Ractor Safety
  #
  # Context itself is NOT shared across Ractors — each Ractor owns its own
  # Context instance.  When a context needs to be handed off (e.g. from a
  # parent agent to a sub-agent) it is first *exported* to an immutable
  # snapshot (a frozen Array of Messages) that can safely cross Ractor
  # boundaries.  The receiving Ractor imports the snapshot and continues
  # building its own mutable Context from that point.
  #
  # ## Design
  #
  #   context = Ragents::Context.new(agent_id: "my_agent")
  #   context.add(Ragents::UserMessage.new(content: "Hello"))
  #   context.add(Ragents::AssistantMessage.new(content: "Hi there!"))
  #
  #   snapshot = context.snapshot   # => frozen Array<Message>
  #   Ractor.new(snapshot) do |snap|
  #     child_ctx = Ragents::Context.import(snap, agent_id: "child")
  #     child_ctx.add(Ragents::UserMessage.new(content: "Follow-up"))
  #   end

  class Context
    attr_reader :agent_id, :id, :metadata

    def initialize(agent_id:, id: nil, metadata: {})
      @agent_id = agent_id.to_s.freeze
      @id = (id || SecureRandom.uuid).freeze
      @messages = []
      @metadata = metadata.freeze
    end

    # Add a message to the history.  Only Message value objects are accepted.
    def add(message)
      unless message.class.include?(MessageBase) ||
             message.class.ancestors.any? { |a| a.is_a?(Module) && a.name&.start_with?("Ragents::") }
        raise ArgumentError, "Expected a Ragents message object, got #{message.class}"
      end

      @messages << message
      self
    end

    alias << add

    # Iterate over messages.
    def each(&block) = @messages.each(&block)

    # Returns a plain Array copy — not the live internal array.
    def messages = @messages.dup

    # Returns the last N messages (default: all).
    def tail(n = @messages.length) = @messages.last(n)

    # Messages formatted for LLM APIs: Array<Hash> with :role and :content.
    # Tool call and result messages include their extended fields.
    def to_api_messages
      @messages.filter_map { |m| message_to_api(m) }
    end

    # Produce a Ractor-safe snapshot of the current history.
    # Returns a frozen Array of frozen Message objects.
    def snapshot
      @messages.map { |m| m.frozen? ? m : m.dup.freeze }.freeze
    end

    # Rebuild a Context from a snapshot produced by #snapshot.
    def self.import(snapshot, agent_id:, id: nil, metadata: {})
      ctx = new(agent_id: agent_id, id: id, metadata: metadata)
      snapshot.each { |m| ctx.instance_variable_get(:@messages) << m }
      ctx
    end

    def size = @messages.size
    def empty? = @messages.empty?

    def system_messages  = @messages.select { |m| m.is_a?(SystemMessage) }
    def user_messages    = @messages.select { |m| m.is_a?(UserMessage) }
    def assistant_messages = @messages.select { |m| m.is_a?(AssistantMessage) }

    # Clear history while keeping system messages (instructions).
    def reset_conversation!
      system = system_messages
      @messages.clear
      system.each { |m| @messages << m }
      self
    end

    def inspect
      "#<Ragents::Context id=#{@id} agent=#{@agent_id} messages=#{@messages.size}>"
    end

    private

    def message_to_api(message)
      case message
      when SystemMessage
        { role: "system", content: message.content }
      when UserMessage
        { role: "user", content: message.content }
      when AssistantMessage
        { role: "assistant", content: message.content }
      when ToolCallMessage
        {
          role: "assistant",
          content: nil,
          tool_calls: [ {
            id: message.tool_call_id,
            type: "function",
            function: {
              name: message.name,
              arguments: JSON.generate(message.arguments)
            }
          } ]
        }
      when ToolResultMessage
        {
          role: "tool",
          tool_call_id: message.tool_call_id,
          content: message.success? ? message.content.to_s : "Error: #{message.error}"
        }
      end
    end
  end
end
