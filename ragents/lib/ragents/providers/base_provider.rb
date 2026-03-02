# frozen_string_literal: true

require "securerandom"
require "json"

module Ragents
  module Providers
    # BaseProvider defines the interface every LLM adapter must implement.
    #
    # ## Ractor Safety
    #
    # Provider instances live inside the Ractor that executes the agent.
    # They are created fresh per-Ractor (not shared) so they carry no
    # cross-Ractor mutable state.
    #
    # The only cross-Ractor state that providers may need (API keys,
    # base URLs) should be passed in as frozen Strings at construction time
    # and stored as frozen instance variables.
    #
    # ## Implementing a Provider
    #
    #   class MyProvider < Ragents::Providers::BaseProvider
    #     def chat(messages:, tools: [], model: nil, **opts)
    #       # Call your API.  Return a GenerationResult.
    #     end
    #   end
    #
    # chat() must return a GenerationResult with:
    #   - content (String) — the assistant's reply text (may be nil if tool calls present)
    #   - tool_calls (Array<ToolCallSpec>) — zero or more tool invocations
    #   - input_tokens, output_tokens (Integer, optional)
    #   - model (String, optional) — model actually used

    # Value object returned by every provider#chat call.
    GenerationResult = Data.define(
      :content,
      :tool_calls,
      :input_tokens,
      :output_tokens,
      :model,
      :stop_reason
    ) do
      def self.new(content: nil, tool_calls: [], input_tokens: nil, output_tokens: nil, model: nil, stop_reason: nil)
        super(
          content: content&.to_s,
          tool_calls: (tool_calls || []).map { |tc| ToolCallSpec.from(tc) }.freeze,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          model: model&.to_s,
          stop_reason: stop_reason&.to_s
        )
      end

      def tool_call? = !tool_calls.empty?
      def done?      = !tool_call?
    end

    # Describes a single tool invocation requested by the LLM.
    ToolCallSpec = Data.define(:id, :name, :arguments) do
      def self.new(id:, name:, arguments: {})
        super(id: id.to_s, name: name.to_s, arguments: arguments.transform_keys(&:to_sym).freeze)
      end

      def self.from(obj)
        return obj if obj.is_a?(ToolCallSpec)

        case obj
        when Hash
          new(id: obj[:id] || obj["id"] || SecureRandom.hex(8),
              name: obj[:name] || obj["name"],
              arguments: obj[:arguments] || obj["arguments"] || {})
        else
          raise TypeError, "Cannot convert #{obj.class} to ToolCallSpec"
        end
      end

      def to_tool_call_message
        ToolCallMessage.new(tool_call_id: id, name: name, arguments: arguments)
      end
    end

    class BaseProvider
      # Subclasses must implement this method.
      #
      # @param messages [Array<Hash>] — API-formatted messages (role/content pairs)
      # @param tools    [Array<Hash>] — JSON Schema tool descriptors
      # @param model    [String, nil] — model override
      # @param **opts   provider-specific options (temperature, max_tokens, …)
      # @return [GenerationResult]
      def chat(messages:, tools: [], model: nil, **opts)
        raise NotImplementedError, "#{self.class}#chat is not implemented"
      end

      # Optional: some providers support embeddings.
      def embed(texts:, model: nil, **opts)
        raise NotImplementedError, "#{self.class}#embed is not implemented"
      end

      protected

      # Helper: parse JSON tool arguments safely.
      def parse_arguments(raw)
        return raw if raw.is_a?(Hash)
        return {} if raw.nil? || raw.strip.empty?

        JSON.parse(raw, symbolize_names: true)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
