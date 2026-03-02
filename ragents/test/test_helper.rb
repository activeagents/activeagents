# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "ragents"
require "minitest/autorun"

# ---------------------------------------------------------------------------
# Helpers available to all tests
# ---------------------------------------------------------------------------
module TestHelpers
  # Build a MockProvider with scripted responses
  def mock_provider(responses: [{ content: "Hello, I am a test assistant." }])
    Ragents::Providers::MockProvider.new(responses: responses)
  end

  # Build an AgentRactor backed by a MockProvider
  def mock_agent(responses: [{ content: "Hello!" }], tools: [], system_prompt: nil, max_iterations: 5)
    Ragents::Ractor::AgentRactor.new(
      provider_class: Ragents::Providers::MockProvider,
      provider_opts: { responses: responses },
      tools: tools,
      system_prompt: system_prompt,
      max_iterations: max_iterations
    )
  end

  # Build a simple Tool
  def echo_tool
    Ragents::Tool.new(
      name: "echo",
      description: "Echoes the input",
      parameters: {
        type: "object",
        properties: { text: { type: "string", description: "Text to echo" } },
        required: ["text"]
      }
    ) { |text:| "ECHO: #{text}" }
  end
end

class Minitest::Test
  include TestHelpers
end
