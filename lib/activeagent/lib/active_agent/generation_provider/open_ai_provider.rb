# frozen_string_literal: true

require 'openai'

module ActiveAgent
  module GenerationProvider
    class OpenAIProvider < Base
      def initialize(config)
        super(config)
        @api_key = config['api_key']
        @model_name = config['model'] || 'gpt-3.5-turbo'
      end

      def generate(agent, stream: nil)
        @agent = agent
        client = OpenAI::Client.new(api_key: @api_key)
        parameters = build_parameters(agent)
        if stream
          parameters[:stream] = true
          client.chat(parameters: parameters) do |chunk, bytesize|
            stream.call(chunk, bytesize)
          end
        else
          response = client.chat(parameters: parameters)
          handle_response(agent, response)
        end
      rescue => e
        handle_error(e)
      end

      private

      def build_parameters(agent)
        {
          model: @model_name,
          messages: build_messages(agent),
          temperature: @config['temperature'] || 0.7
        }
      end

      def build_messages(agent)
        messages = []
        if agent.instructions.present?
          system_message = { role: 'system', content: agent.instructions }
          messages << system_message
        end
        if agent.content.present?
          user_message = { role: 'user', content: agent.content }
          messages << user_message
        end
        messages
      end

      def handle_response(agent, response)
        adapter = response_class.new(response)
        agent.message = Message.create(
          chat_id: agent.context[:chat_id],
          role: 'assistant',
          content: adapter.content
        )
      end

      def handle_error(error)
        Rails.logger.error "OpenAIProvider Error: #{error.message}"
        raise error
      end

      class Response < GenerationProvider::Response
        def content
          response.dig('choices', 0, 'message', 'content')
        end
      end
    end
  end
end
