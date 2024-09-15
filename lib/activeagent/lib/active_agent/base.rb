# lib/active_agent/base.rb
module ActiveAgent
  class Base
    include ActiveModel::Model
    extend ActiveModel::Callbacks
    
    attr_accessor :reponse, :messages

    define_model_callbacks :generate

    before_generate :handle_stream
    after_generate :perform_action
    after_generate :broadcast_stream

    class << self
      attr_accessor :generation_provider

      def generate_with(provider_name = :default, options = {})
        config = ActiveAgent.config[provider_name.to_s] || ActiveAgent.config[ENV['RAILS_ENV']]
        @generation_provider = configure_provider(config)
        self
      end

      def generate(prompt:, **options)
        options[:stream] = handle_stream if options[:stream]
        new.generate(prompt:, **options)
      end

      private

      def configure_provider(config)
        require "active_agent/generation_provider/#{config['service'].underscore}_provider"
        ActiveAgent::GenerationProvider.const_get(:"#{config['service'].camelize}Provider").new(config)
      rescue LoadError
        raise "Missing generation provider for #{config['service'].inspect}"
      end
    end

    def handle_stream(&block)
      proc do |chunk, _bytesize|
        new_content = provider_stream_handler
        block.call(new_content) if block_given? && new_content
      end
    end
    
    def perform_action
      Rails.logger.info "Action performed"
      prerform_provider_action(@response)
    end

    def broadcast_stream
      Rails.logger.info "Broadcasting stream"
    end    
    
    def generate(prompt:, **options)
      run_callbacks :generate do
        @response = provider_generate(prompt: prompt, **options)
      end

      @response.dig("choices", 0, "message", "content")
    end

    private
      def provider_stream_handler(&block)
        self.class.generation_provider.handle_stream
      end

      def prerform_provider_action(response)
        self.class.generation_provider.perform_action(response)
      end

      def provider_generate(prompt:, **options)
        self.class.generation_provider.generate(prompt:, **options)
      end
  end
end
