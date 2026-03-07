# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Ragents
  module Providers
    # OpenAI-compatible provider using only stdlib Net::HTTP — no SDK dependency.
    #
    # Works with:
    #   - OpenAI (https://api.openai.com/v1)
    #   - Azure OpenAI (supply base_url)
    #   - Ollama (http://localhost:11434/v1, no api_key required)
    #   - OpenRouter (https://openrouter.ai/api/v1)
    #   - Any OpenAI-compatible API
    #
    # ## Ractor Safety
    #
    # Instances store only frozen Strings (api_key, base_url, default_model).
    # Net::HTTP connections are created per request — not shared.
    class OpenAIProvider < BaseProvider
      DEFAULT_BASE_URL   = "https://api.openai.com/v1"
      DEFAULT_MODEL      = "gpt-4o-mini"
      DEFAULT_MAX_TOKENS = 4096
      READ_TIMEOUT       = 120
      OPEN_TIMEOUT       = 10

      def initialize(api_key: nil, base_url: nil, default_model: nil)
        @api_key       = (api_key || ENV.fetch("OPENAI_API_KEY", "")).freeze
        @base_url      = (base_url || DEFAULT_BASE_URL).chomp("/").freeze
        @default_model = (default_model || DEFAULT_MODEL).freeze
        freeze
      end

      # @param messages [Array<Hash>] role/content pairs
      # @param tools    [Array<Hash>] JSON Schema tool descriptors
      # @param model    [String, nil]
      # @param temperature [Float]
      # @param max_tokens  [Integer]
      # @param stream   [Boolean] (not yet supported in provider — use streaming concern)
      # @return [GenerationResult]
      def chat(messages:, tools: [], model: nil, temperature: 0.7, max_tokens: DEFAULT_MAX_TOKENS, **opts)
        body = build_request_body(
          messages: messages,
          tools: tools,
          model: model || @default_model,
          temperature: temperature,
          max_tokens: max_tokens,
          **opts
        )

        response = post("/chat/completions", body)
        parse_response(response)
      end

      def embed(texts:, model: "text-embedding-3-small", dimensions: nil, **_opts)
        body = { model: model, input: Array(texts) }
        body[:dimensions] = dimensions if dimensions

        response = post("/embeddings", body)
        data = response["data"]&.map { |d| d["embedding"] } || []
        data.first(1).first || data
      end

      private

      def build_request_body(messages:, tools:, model:, temperature:, max_tokens:, **opts)
        body = {
          model: model,
          messages: messages,
          temperature: temperature,
          max_tokens: max_tokens
        }

        body[:tools] = tools unless tools.empty?
        body[:tool_choice] = "auto" unless tools.empty?
        body.merge!(opts.slice(:stream, :response_format, :top_p, :frequency_penalty, :presence_penalty))
        body
      end

      def post(path, body)
        uri = URI.parse("#{@base_url}#{path}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = READ_TIMEOUT
        http.open_timeout = OPEN_TIMEOUT

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"]  = "application/json"
        request["Authorization"] = "Bearer #{@api_key}" unless @api_key.empty?

        request.body = JSON.generate(body)

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "OpenAI API error #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      end

      def parse_response(data)
        choice     = data.dig("choices", 0) || {}
        message    = choice["message"] || {}
        usage      = data["usage"] || {}
        tool_calls = parse_tool_calls(message["tool_calls"])

        GenerationResult.new(
          content: message["content"],
          tool_calls: tool_calls,
          input_tokens: usage["prompt_tokens"],
          output_tokens: usage["completion_tokens"],
          model: data["model"],
          stop_reason: choice["finish_reason"]
        )
      end

      def parse_tool_calls(raw_calls)
        return [] unless raw_calls.is_a?(Array)

        raw_calls.map do |tc|
          fn = tc["function"] || {}
          ToolCallSpec.new(
            id: tc["id"] || SecureRandom.hex(8),
            name: fn["name"],
            arguments: parse_arguments(fn["arguments"])
          )
        end
      end
    end
  end
end
