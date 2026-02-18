# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Helper to create a user
    def create_user(email: "user#{SecureRandom.hex(4)}@example.com", password: "password123")
      User.create!(
        email_address: email,
        password: password,
        password_confirmation: password
      )
    end

    # Helper to create an agent for a user
    def create_agent(user:, name: "Test Agent", **attrs)
      defaults = {
        name: name,
        description: "A test agent",
        provider: "openai",
        model: "gpt-4o-mini",
        preset_type: "terminal",
        instructions: "You are a helpful assistant.",
        status: :draft
      }
      user.agents.create!(defaults.merge(attrs))
    end

    # Helper to create a run for an agent
    def create_run(agent:, **attrs)
      defaults = {
        input_prompt: "Test prompt",
        output: "Test response",
        status: :complete,
        input_tokens: 10,
        output_tokens: 20,
        total_tokens: 30,
        duration_ms: 1000,
        started_at: Time.current,
        completed_at: Time.current + 1.second
      }
      agent.agent_runs.create!(defaults.merge(attrs))
    end
  end
end

module ActionDispatch
  class IntegrationTest
    # Helper to sign in as a user
    def sign_in_as(user)
      post "/session", params: {
        email_address: user.email_address,
        password: "password123"
      }
    end

    # Helper for JSON requests
    def json_response
      JSON.parse(response.body)
    end
  end
end
