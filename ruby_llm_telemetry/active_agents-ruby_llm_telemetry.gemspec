# frozen_string_literal: true

require_relative "lib/active_agents/ruby_llm_telemetry/version"

Gem::Specification.new do |spec|
  spec.name = "active_agents-ruby_llm_telemetry"
  spec.version = ActiveAgents::RubyLLMTelemetry::VERSION
  spec.authors = [ "ActiveAgents" ]
  spec.email = [ "hello@activeagents.ai" ]

  spec.summary = "Report RubyLLM chats to an ActiveAgents trace endpoint"
  spec.description = <<~DESC
    Subscribes to RubyLLM's instrumentation events and reports each chat turn
    as a trace — a root span, an llm span, and a span per tool call — to the
    ActiveAgents platform or any self-hosted ActiveAgent dashboard
    (POST /v1/traces). Works with apps built directly on RubyLLM: no
    ActiveAgent framework dependency, nothing beyond ActiveSupport and stdlib.
  DESC

  spec.homepage = "https://github.com/activeagents/activeagents"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "#{spec.homepage}/tree/main/ruby_llm_telemetry"
  }

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "activesupport", ">= 7.0"
end
