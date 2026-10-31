# The base agent. Picks the generation provider from the environment:
# AI_PROVIDER wins; otherwise whichever real provider has a key; otherwise
# the framework's mock provider, which needs no credentials and lets the
# whole product loop run offline (see config/active_agent.yml).
class ApplicationAgent < ActiveAgent::Base
  PROVIDER = ENV.fetch("AI_PROVIDER") {
    if ENV["OPENAI_API_KEY"].present?
      "openai"
    elsif ENV["ANTHROPIC_API_KEY"].present?
      "anthropic"
    elsif ENV["OPENROUTER_API_KEY"].present?
      "openrouter"
    else
      "mock"
    end
  }.to_sym

  generate_with PROVIDER

  def self.mock?
    PROVIDER == :mock
  end

  private

  # Gives the generation a trace id before prompting. The telemetry trace and
  # the solid_agent generation row both read it from prompt_options, which is
  # what lets a run in this app link to its trace on the dashboard.
  def new_trace!(trace_id = nil)
    prompt_options[:trace_id] = trace_id.presence || SecureRandom.uuid
  end
end
