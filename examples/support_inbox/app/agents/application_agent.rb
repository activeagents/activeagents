class ApplicationAgent < ActiveAgent::Base
  # Provider resolution: AI_PROVIDER wins, otherwise pick whichever real
  # provider has credentials, otherwise the gem's mock provider (works
  # without any keys — see config/active_agent.yml).
  PROVIDER = ENV.fetch("AI_PROVIDER") {
    if ENV["OPENAI_API_KEY"].present?
      "openai"
    elsif ENV["ANTHROPIC_API_KEY"].present?
      "anthropic"
    else
      "mock"
    end
  }.to_sym

  generate_with PROVIDER

  private

  # Give each generation its own trace id before prompting. The telemetry
  # trace and the solid_agent generation record both read it from
  # prompt_options, which is what lets a conversation row in this app's
  # database link to its trace on the monitoring dashboard.
  def new_trace!
    prompt_options[:trace_id] = SecureRandom.uuid
  end
end
