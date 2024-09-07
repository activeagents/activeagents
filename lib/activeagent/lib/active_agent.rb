# lib/active_agent.rb
require 'yaml'
require "active_support"
require 'active_agent/base'
require 'active_agent/provider'
require 'active_agent/provider/openai_provider'

module ActiveAgent
  extend ActiveSupport::Autoload

  autoload :Service
  
  class << self
    attr_accessor :config

    def configure
      yield self
    end

    def load_configuration(file)
      @config = config_file = YAML.load_file(file, aliases: true)
      # env = ENV['RAILS_ENV'] || ENV['ENV'] || 'development'
      # @config = config_file[env]
    end
  end
end
