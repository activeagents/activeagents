require 'open_router'

module ActiveAgent
  class Service::OpenRouter < Service
    def initialize(**options)
      @options = options
    end

    def call(env)
      env[:url] = env[:url].dup
      env[:url].host = @options[:host] if @options[:host]
      env[:url].port = @options[:port] if @options[:port]
      env[:url].scheme = @options[:scheme] if @options[:scheme]
      env
    end
  end
end