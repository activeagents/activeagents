# frozen_string_literal: true

module ActiveAgent
  module GenerationProvider
    class Base
      attr_reader :agent

      def initialize(config)
        @config = config
      end

      def generate(agent, stream: nil)
        raise NotImplementedError, "Subclasses must implement the generate method"
      end

      def self.configure_provider(config)
        require "active_agent/generation_provider/#{config['service'].underscore}_provider"
        ActiveAgent::GenerationProvider.const_get("#{config['service'].camelize}Provider").new(config)
      rescue LoadError
        raise "Missing generation provider for #{config['service'].inspect}"
      end

      def response_class
        ActiveAgent::GenerationProvider::Response
      end
    end
  end
end
