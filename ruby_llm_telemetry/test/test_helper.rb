# frozen_string_literal: true

require "minitest/autorun"
require "active_agents/ruby_llm_telemetry"

module TelemetryTestHelpers
  Msg = Struct.new(:role, :input_tokens, :output_tokens, :thinking_tokens, :content)

  def setup
    @posted = []
    subscribe
  end

  def teardown
    ActiveAgents::RubyLLMTelemetry.unsubscribe!
    ActiveAgents::RubyLLMTelemetry.clear_state
    Thread.current[ActiveAgents::RubyLLMTelemetry::AGENT_KEY] = nil
  end

  attr_reader :posted

  # Captures the built payload instead of delivering it.
  def subscribe(**options)
    ActiveAgents::RubyLLMTelemetry.unsubscribe!
    ActiveAgents::RubyLLMTelemetry.subscribe!(
      api_key: "test-key", service_name: "test-app", environment: "test", async: false, **options
    )
    captured = @posted
    ActiveAgents::RubyLLMTelemetry.singleton_class.define_method(:post_traces) { |body| captured << body }
  end

  def instrument(name, payload, &block)
    ActiveSupport::Notifications.instrument(name, payload, &block)
  end

  def assistant(input:, output:, thinking: 0, content: nil)
    Msg.new("assistant", input, output, thinking, content)
  end

  def user(content)
    Msg.new("user", nil, nil, nil, content)
  end

  def system_message(content)
    Msg.new("system", nil, nil, nil, content)
  end

  def chat_payload(input_messages: [ Msg.new("user") ], chat: default_chat, **extra)
    { chat: chat, provider: :openai, model: "gpt-4o", input_messages: input_messages, streaming: false }.merge(extra)
  end

  def default_chat
    @default_chat ||= Object.new
  end

  def traces
    posted.map { |body| body.fetch("traces").first }
  end

  def spans_of(trace, type)
    trace.fetch("spans").select { |span| span["type"] == type }
  end
end
