# lib/active_agent/base.rb
module ActiveAgent
  class Base
    include ActiveModel::Model
    include ActiveModel::Callbacks
    
    define_model_callbacks :generate
    after_generate :perform_action
    after_generate :broadcast_stream

    class << self
      attr_accessor :provider, :model

      def generate_with(provider_name = :default, options = {})
        config = ActiveAgent.config[provider_name.to_s] || ActiveAgent.config[ENV['RAILS_ENV']]
        @provider = load_provider(config)
        @model = options[:model] || config['model']
      end

      def generate(prompt:, **options)
        @provider.generate(prompt:, **options)
      end

      private

      def load_provider(config)
        case config['service']
        when 'OpenAI'
          ActiveAgent::Provider::OpenAIProvider.new(config)
        else
          raise "Unknown service provider: #{config['service']}"
        end
      end
    end

    def generate_stream(prompt:, **options)
      content = ""
      stream = proc do |chunk, _bytesize|
        content_change = chunk.dig("choices", 0, "delta", "content")
        content += content_change
        puts content
      end
      @provider.generate(prompt: prompt, stream: stream, **options)
    end
  end
end
