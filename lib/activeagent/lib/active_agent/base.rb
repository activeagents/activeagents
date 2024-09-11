# lib/active_agent/base.rb
module ActiveAgent
  class Base
    include ActiveModel::Model
    extend ActiveModel::Callbacks
    
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
        run_callbacks :generate do
          @provider.generate(prompt:, **options)
        end
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

    def generate(prompt:, **options)
      self.class.run_callbacks :generate do
        self.class.provider.generate(prompt:, **options)
      end
    end

    def generate_stream(prompt:, **options)
      content = ""
      stream = proc do |chunk, _bytesize|
        content_change = chunk.dig("choices", 0, "delta", "content")
        content += content_change
        puts content
      end
      self.class.provider.generate(prompt: prompt, stream: stream, **options)
    end
    
    def perform_action
      Rails.logger.info "Action performed"
    end

    def broadcast_stream
      Rails.logger.info "Action performed"
    end
  end
end
