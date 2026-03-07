# frozen_string_literal: true

require "json"
require "securerandom"

require_relative "ragents/version"
require_relative "ragents/message"
require_relative "ragents/context"
require_relative "ragents/tool"
require_relative "ragents/providers/base_provider"
require_relative "ragents/providers/mock_provider"
require_relative "ragents/providers/simulated_provider"
require_relative "ragents/providers/async_simulated_provider"
require_relative "ragents/providers/realistic_llm_provider"
require_relative "ragents/providers/openai_provider"
require_relative "ragents/providers/anthropic_provider"
require_relative "ragents/ractor/agent_ractor"
require_relative "ragents/ractor/supervisor"
require_relative "ragents/ractor/pool"

# Ragents — Ractor-based AI Agents for Ruby 4.x
#
# Ragents brings the Ractor concurrency model to AI agent orchestration.
# Each agent turn runs in its own Ractor with its own GVL, enabling true
# multi-core parallelism for I/O-heavy LLM workloads.
#
# ## Quick Start
#
#   require "ragents"
#
#   # Simple single agent
#   agent = Ragents::Ractor::AgentRactor.new(
#     provider_class: Ragents::Providers::OpenAIProvider,
#     provider_opts:  { api_key: ENV["OPENAI_API_KEY"] },
#     system_prompt:  "You are a helpful assistant"
#   )
#
#   result = agent.run("What is the capital of France?")
#   puts result.content  # => "Paris..."
#
# ## With Tools
#
#   search_tool = Ragents::Tool.new(
#     name: "search",
#     description: "Search the web",
#     parameters: { type: "object", properties: { query: { type: "string" } }, required: ["query"] }
#   ) { |query:| "Results for #{query}..." }
#
#   agent = Ragents::Ractor::AgentRactor.new(
#     provider_class: Ragents::Providers::OpenAIProvider,
#     provider_opts:  { api_key: ENV["OPENAI_API_KEY"] },
#     tools: [search_tool]
#   )
#
# ## Parallel Processing
#
#   pool = Ragents::Ractor::AgentPool.new(
#     size: 8,
#     provider_class: Ragents::Providers::OpenAIProvider,
#     provider_opts:  { api_key: ENV["OPENAI_API_KEY"] }
#   )
#
#   results = pool.process(["Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7", "Q8"])
#
# ## Agent-as-a-Tool (Multi-Agent Orchestration)
#
#   supervisor = Ragents::Ractor::Supervisor.new
#   supervisor.register("researcher", provider_class: Ragents::Providers::OpenAIProvider, ...)
#   supervisor.register("writer",     provider_class: Ragents::Providers::OpenAIProvider, ...)
#
#   # Let the orchestrator call researcher and writer as tools
#   orchestrator = Ragents::Ractor::AgentRactor.new(
#     provider_class: Ragents::Providers::OpenAIProvider,
#     tools: [
#       supervisor.agent_tool("researcher", description: "Research a topic"),
#       supervisor.agent_tool("writer",     description: "Write content")
#     ]
#   )

# CLI components are loaded on demand (require "ragents/cli/tui" etc.) to avoid
# pulling in io/console when ragents is used as a library.

module Ragents
  # Base error class
  class Error < StandardError; end

  # Raised when the agent exceeds its maximum iteration count
  class MaxIterationsError < Error; end

  # Raised when a tool is called that is not registered
  class UnknownToolError < Error; end
end
