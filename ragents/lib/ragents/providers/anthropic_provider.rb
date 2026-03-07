# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Ragents
  module Providers
    # Anthropic Claude provider using only stdlib Net::HTTP.
    #
    # Supports:
    #   - Claude 3.5 Sonnet / Haiku / Opus
    #   - Tool use (function calling)
    #   - System messages
    #
    # ## Ractor Safety
    #
    # Same as OpenAIProvider: only frozen Strings stored, per-request connections.
    class AnthropicProvider < BaseProvider
      BASE_URL           = "https://api.anthropic.com/v1"
      DEFAULT_MODEL      = "claude-3-5-haiku-latest"
      DEFAULT_MAX_TOKENS = 4096
      API_VERSION        = "2023-06-01"
      READ_TIMEOUT       = 120
      OPEN_TIMEOUT       = 10

      def initialize(api_key: nil, default_model: nil)
        @api_key       = (api_key || ENV.fetch("ANTHROPIC_API_KEY", "")).freeze
        @default_model = (default_model || DEFAULT_MODEL).freeze
        freeze
      end

      def chat(messages:, tools: [], model: nil, temperature: 0.7, max_tokens: DEFAULT_MAX_TOKENS, **opts)
        # Anthropic separates system messages from the message array
        system_content = extract_system(messages)
        conversation   = messages.reject { |m| m[:role] == "system" }

        body = build_request_body(
          messages: conversation,
          system: system_content,
          tools: tools,
          model: model || @default_model,
          temperature: temperature,
          max_tokens: max_tokens,
          **opts
        )

        response = post("/messages", body)
        parse_response(response)
      end

      private

      def extract_system(messages)
        system_msgs = messages.select { |m| m[:role] == "system" || m["role"] == "system" }
        return nil if system_msgs.empty?

        system_msgs.map { |m| m[:content] || m["content"] }.join("\n\n")
      end

      def build_request_body(messages:, system:, tools:, model:, temperature:, max_tokens:, **opts)
        body = {
          model: model,
          max_tokens: max_tokens,
          temperature: temperature,
          messages: messages
        }

        body[:system] = system if system

        unless tools.empty?
          # Anthropic uses a slightly different tool schema format
          body[:tools] = tools.map { |t| anthropic_tool(t) }
        end

        body
      end

      def anthropic_tool(schema)
        fn = schema.dig(:function) || schema.dig("function") || schema
        {
          name: fn[:name] || fn["name"],
          description: fn[:description] || fn["description"],
          input_schema: fn[:parameters] || fn["parameters"] || { type: "object", properties: {} }
        }
      end

      def post(path, body)
        uri = URI.parse("#{BASE_URL}#{path}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = READ_TIMEOUT
        http.open_timeout = OPEN_TIMEOUT

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"]  = "application/json"
        request["x-api-key"]     = @api_key
        request["anthropic-version"] = API_VERSION

        request.body = JSON.generate(body)

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "Anthropic API error #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      end

      def parse_response(data)
        content_blocks = data["content"] || []
        text_content   = content_blocks.select { |b| b["type"] == "text" }
                                       .map { |b| b["text"] }
                                       .join
        tool_calls     = parse_tool_calls(content_blocks)
        usage          = data["usage"] || {}

        GenerationResult.new(
          content: text_content.empty? ? nil : text_content,
          tool_calls: tool_calls,
          input_tokens: usage["input_tokens"],
          output_tokens: usage["output_tokens"],
          model: data["model"],
          stop_reason: data["stop_reason"]
        )
      end

      def parse_tool_calls(blocks)
        blocks.select { |b| b["type"] == "tool_use" }.map do |b|
          ToolCallSpec.new(
            id: b["id"] || SecureRandom.hex(8),
            name: b["name"],
            arguments: b["input"] || {}
          )
        end
      end
    end
  end
end
