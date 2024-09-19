# lib/active_agent/generation.rb
require 'delegate'

module ActiveAgent
  class Generation < Delegator
    def initialize(agent_class, action, *args)
      @agent_class = agent_class
      @action = action
      @args = args
      @processed_agent = nil
      @message = nil
    end
    ruby2_keywords(:initialize)

    def __getobj__
      @message ||= processed_agent.message
    end

    def __setobj__(message)
      @message = message
    end

    def message
      __getobj__
    end

    def processed?
      @processed_agent || @message
    end

    def generate_now
      processed_agent.handle_exceptions do
        processed_agent.run_callbacks(:generate) do
          processed_agent.perform_generation
        end
      end
    end

    def generate_later(options = {})
      if processed?
        raise "You've accessed the message before asking to generate it later."
      else
        @agent_class.generation_job.set(options).perform_later(
          @agent_class.name, @action.to_s, args: @args
        )
      end
    end

    private

    def processed_agent
      @processed_agent ||= @agent_class.new.tap do |agent|
        agent.process(@action, *@args)
      end
    end
  end
end
