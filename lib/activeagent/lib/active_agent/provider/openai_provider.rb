# lib/active_agent/providers/openai_provider.rb
require 'openai'
require_relative '../provider'

module ActiveAgent
  module Provider
    class OpenAIProvider
      include ActiveAgent::Provider

      def initialize(config)
        @client = OpenAI::Client.new(api_key: config['api_key'])
        @model = config['model']
      end

      def generate(prompt:, **options)
        instructions = options[:instructions] || prompt
        response = @client.chat(
          parameters: {
            model: options[:model] || @model,
            messages: [{ role: 'system', content: instructions }] + (options[:messages] || []) + [{ role: 'user', content: prompt }],
            temperature: options[:temperature] || 0.7,
            max_tokens: options[:max_tokens] || 100,
            stream: options[:stream] || false
          }
        )
        response.dig("choices", 0, "message", "content")
      end
    end
  end
end
