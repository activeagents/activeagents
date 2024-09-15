# lib/active_agent/providers/openai_provider.rb
require 'openai'
require_relative '../generation_provider'

module ActiveAgent
  module GenerationProvider
    class OpenAIProvider
      include ActiveAgent::GenerationProvider

      def initialize(config)
        @client = OpenAI::Client.new(api_key: config['api_key'])
        @model = config['model']
      end

      def generate(prompt:, **options)
        instructions = options[:instructions] || prompt
        @client.chat(
          parameters: {
            model: options[:model] || @model,
            messages: [{ role: 'system', content: instructions }] + (options[:messages] || []) + [{ role: 'user', content: prompt }],
            temperature: options[:temperature] || 0.7,
            max_tokens: options[:max_tokens] || 100,
            stream: options[:stream] || false
          }
        )
      end
      
      def handle_stream
        proc do |chunk, _bytesize|
          new_content = chunk.dig("choices", 0, "delta", "content")
          yield new_content if new_content
        end
      end

      def perform_action(response)
        message = response.dig("choices", 0, "message")

        if message["role"] == "assistant" && message["tool_calls"]
          message["tool_calls"].each do |tool_call|
            tool_call_id = tool_call.dig("id")
            function_name = tool_call.dig("function", "name")
            function_args = JSON.parse(
              tool_call.dig("function", "arguments"),
              { symbolize_names: true },
            )

            Rails.logger.info "OpenAI requested action #{tool_call_id} #{function_name} with args #{function_args}" 
          end
        end
      end
    end
  end
end
