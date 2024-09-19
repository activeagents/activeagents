# frozen_string_literal: true

module ActiveAgent
  module GenerationProvider
    def self.for(provider_name)
      config = ActiveAgent.config[provider_name.to_s] || ActiveAgent.config[ENV['RAILS_ENV']][provider_name.to_s]
      raise "Configuration not found for provider: #{provider_name}" unless config

      Base.configure_provider(config)
    end
  end
end
