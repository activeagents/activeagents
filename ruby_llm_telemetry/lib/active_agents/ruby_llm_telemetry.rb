# frozen_string_literal: true

require "net/http"
require "json"
require "securerandom"
require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/filters"
require "active_support/core_ext/time"

require_relative "ruby_llm_telemetry/version"

module ActiveAgents
  # Reports RubyLLM chats to an ActiveAgents-compatible trace endpoint
  # (POST /v1/traces — the wire format ActiveAgent::Telemetry uses).
  #
  # Requires RubyLLM.config.instrumenter = ActiveSupport::Notifications.
  #
  # One trace per conversation turn: a root span, an llm span covering the
  # whole provider loop, and a tool span per tool_call.ruby_llm event.
  #
  # RubyLLM emits a chat.ruby_llm event per provider round, and the two
  # generations of the gem arrange those rounds differently: through 1.x a
  # tool round recurses inside the enclosing event, while 2.x drives a flat
  # `step until complete?` loop whose rounds are siblings with tool calls
  # firing between them. Rounds are therefore accumulated and flushed on the
  # round that ends the turn — the one that errors or answers without
  # requesting tools — which yields the same trace under both arrangements.
  # Tokens are summed per round from the assistant messages that round added,
  # so a repeated event-level count is never double counted.
  #
  # Tool arguments and results are never sent; error messages are truncated.
  module RubyLLMTelemetry
    DEFAULT_ENDPOINT = 'https://api.activeagents.ai/v1/traces'.freeze
    AGENT_KEY = :active_agents_ruby_llm_agent
    STATE_KEY = :active_agents_ruby_llm_state
    TOOL_STARTED_AT_KEY = :_active_agents_started_at
    ERROR_MESSAGE_LIMIT = 200
    # A turn that never reaches a final round (a halted tool call, or an app
    # driving RubyLLM 2.x's `step` by hand) would otherwise accumulate forever.
    MAX_TURN_SECONDS = 600

    State = Struct.new(:depth, :started_at, :tool_spans, :rounds, :tokens, :chat_key)

    class << self
      attr_reader :endpoint, :api_key, :service_name, :environment

      # agent_resolver: optional callable receiving the chat event payload and
      # returning { name:, action: }, so traffic can be attributed from an
      # initializer alone; an enclosing with_agent block still wins. RubyLLM
      # carries no application identity on the payload — neither RubyLLM::Agent
      # nor an acts_as_chat record reaches the instrumenter — so unattributed
      # traffic reports as RubyLLM::Chat.
      def subscribe!(api_key:, endpoint: DEFAULT_ENDPOINT, service_name: nil, environment: nil, agent_resolver: nil, async: true)
        @api_key = api_key
        @endpoint = endpoint
        @service_name = service_name || default_service_name
        @environment = environment || default_environment
        @agent_resolver = agent_resolver
        @async = async

        @subscriptions ||= [
          ActiveSupport::Notifications.subscribe('chat.ruby_llm', ChatSubscriber.new),
          ActiveSupport::Notifications.subscribe('tool_call.ruby_llm', ToolCallSubscriber.new)
        ]
      end

      def unsubscribe!
        Array(@subscriptions).each { |subscription| ActiveSupport::Notifications.unsubscribe(subscription) }
        @subscriptions = nil
      end

      # Attributes traces inside the block to a named agent/action.
      def with_agent(name, action: 'chat')
        previous = Thread.current[AGENT_KEY]
        Thread.current[AGENT_KEY] = { name: name, action: action }
        yield
      ensure
        Thread.current[AGENT_KEY] = previous
      end

      def state
        Thread.current[STATE_KEY] ||= State.new(0, nil, [], 0, zero_tokens, nil)
      end

      def clear_state
        Thread.current[STATE_KEY] = nil
      end

      # Reports whatever the current turn has accumulated. Apps that drive
      # RubyLLM 2.x's `step`/`run_tools` themselves can call this to close a
      # turn that ends while tool calls are still pending.
      def flush!(payload = {})
        turn = Thread.current[STATE_KEY]
        return if turn.nil? || turn.rounds.zero?

        clear_state
        report_turn(payload, turn)
      end

      def begin_round(payload)
        turn = state
        if turn.depth.zero?
          chat_key = payload[:chat].object_id
          flush! if turn.rounds.positive? && (turn.chat_key != chat_key || turn_expired?(turn))
          turn = state
          turn.chat_key = chat_key
          turn.started_at ||= Time.current
        end
        turn.depth += 1
      end

      def finish_round(payload)
        turn = state
        turn.depth -= 1
        return unless turn.depth.zero?

        turn.rounds += 1
        accumulate_tokens(turn, payload)
        flush!(payload) if payload[:exception_object] || !payload[:tool_call]
      end

      def build_tool_span(payload, started_at, finished_at)
        error = payload[:exception_object]
        attributes = { 'tool.name' => payload[:tool_name].to_s, 'tool.call_id' => payload[:tool_call_id].to_s }
        attributes.merge!(error_attributes(error)) if error

        {
          'span_id' => SecureRandom.hex(8),
          'name' => "tool.#{payload[:tool_name]}",
          'type' => 'tool',
          'start_time' => started_at.utc.iso8601(6),
          'end_time' => finished_at.utc.iso8601(6),
          'duration_ms' => duration_ms(started_at, finished_at),
          'status' => error ? 'ERROR' : 'OK',
          'attributes' => attributes,
          'tokens' => zero_tokens,
          'events' => []
        }
      end

      private

      def report_turn(payload, turn)
        agent = Thread.current[AGENT_KEY] || resolve_agent(payload) || { name: 'RubyLLM::Chat', action: 'chat' }
        trace_id = SecureRandom.hex(16)
        root_id = SecureRandom.hex(8)
        llm_id = SecureRandom.hex(8)
        started_at = turn.started_at || Time.current
        finished_at = Time.current
        error = payload[:exception_object]

        base = {
          'trace_id' => trace_id,
          'start_time' => started_at.utc.iso8601(6),
          'end_time' => finished_at.utc.iso8601(6),
          'duration_ms' => duration_ms(started_at, finished_at),
          'status' => error ? 'ERROR' : 'OK',
          'events' => []
        }

        root_attributes = {
          'agent.class' => agent[:name],
          'agent.action' => agent[:action],
          'agent.provider' => payload[:provider].to_s,
          'agent.model' => payload[:model].to_s
        }
        root_attributes.merge!(error_attributes(error)) if error

        root_span = base.merge(
          'span_id' => root_id, 'parent_span_id' => nil,
          'name' => "#{agent[:name]}.#{agent[:action]}", 'type' => 'root',
          'attributes' => root_attributes,
          'tokens' => zero_tokens
        )

        llm_span = base.merge(
          'span_id' => llm_id, 'parent_span_id' => root_id,
          'name' => 'llm.generate', 'type' => 'llm',
          'attributes' => {
            'llm.provider' => payload[:provider].to_s,
            'llm.model' => payload[:model].to_s,
            'llm.rounds' => turn.rounds,
            'llm.streaming' => payload[:streaming] || false
          },
          'tokens' => turn.tokens
        )

        tool_spans = turn.tool_spans.map { |span| span.merge('trace_id' => trace_id, 'parent_span_id' => llm_id) }

        post_traces(
          'traces' => [{
            'trace_id' => trace_id,
            'service_name' => service_name,
            'environment' => environment,
            'timestamp' => finished_at.utc.iso8601(6),
            'resource_attributes' => {},
            'spans' => [root_span, llm_span] + tool_spans
          }],
          'sdk' => { 'name' => 'active_agents-ruby_llm_telemetry', 'version' => VERSION, 'language' => 'ruby', 'runtime_version' => RUBY_VERSION }
        )
      end

      def turn_expired?(turn)
        turn.started_at.nil? || (Time.current - turn.started_at) > MAX_TURN_SECONDS
      end

      def accumulate_tokens(turn, payload)
        round_tokens = token_totals(payload)
        turn.tokens = turn.tokens.merge(round_tokens) { |_key, carried, added| carried + added }
      end

      def resolve_agent(payload)
        agent = @agent_resolver&.call(payload)
        return unless agent.is_a?(Hash) && agent[:name].present?

        { name: agent[:name], action: agent[:action] || 'chat' }
      rescue StandardError => e
        warn "[ActiveAgents::RubyLLMTelemetry] agent_resolver failed: #{e.class}: #{e.message}"
        nil
      end

      def default_service_name
        defined?(Rails) ? Rails.application.class.module_parent_name.underscore : 'ruby_llm'
      end

      def default_environment
        defined?(Rails) ? Rails.env : ENV.fetch('RACK_ENV', 'production')
      end

      def duration_ms(started_at, finished_at)
        ((finished_at - started_at) * 1000).round(2)
      end

      def error_attributes(error)
        { 'error.type' => error.class.name, 'error.message' => error.message.to_s.truncate(ERROR_MESSAGE_LIMIT) }
      end

      def zero_tokens
        { 'input' => 0, 'output' => 0, 'thinking' => 0, 'total' => 0 }
      end

      def token_totals(payload)
        initial_count = Array(payload[:input_messages]).size
        new_messages = Array(payload[:messages_after])[initial_count..] || []
        assistant_messages = new_messages.select { |message| message.respond_to?(:role) && message.role.to_s == 'assistant' }

        tokens = {
          'input' => sum_tokens(assistant_messages, :input_tokens),
          'output' => sum_tokens(assistant_messages, :output_tokens),
          'thinking' => sum_tokens(assistant_messages, :thinking_tokens)
        }
        tokens['total'] = tokens.values.sum
        tokens
      end

      def sum_tokens(messages, method_name)
        messages.sum { |message| message.respond_to?(method_name) ? message.public_send(method_name).to_i : 0 }
      end

      def post_traces(body)
        return deliver(body) unless @async

        Thread.new { deliver(body) }
      end

      def deliver(body)
        uri = URI.parse(endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request['Authorization'] = "Bearer #{api_key}"
        request.body = JSON.generate(body)
        http.request(request)
      rescue StandardError => e
        warn "[ActiveAgents::RubyLLMTelemetry] #{e.class}: #{e.message}"
      end
    end

    # Evented ActiveSupport::Notifications subscriber; finish fires even when
    # the instrumented block raises, with the exception on the payload.
    class ChatSubscriber
      def start(_name, _id, payload)
        RubyLLMTelemetry.begin_round(payload)
      rescue StandardError => e
        warn "[ActiveAgents::RubyLLMTelemetry] #{e.class}: #{e.message}"
      end

      def finish(_name, _id, payload)
        RubyLLMTelemetry.finish_round(payload)
      rescue StandardError => e
        warn "[ActiveAgents::RubyLLMTelemetry] #{e.class}: #{e.message}"
        RubyLLMTelemetry.clear_state
      end
    end

    class ToolCallSubscriber
      def start(_name, _id, payload)
        payload[TOOL_STARTED_AT_KEY] = Time.current
      end

      def finish(_name, _id, payload)
        started_at = payload.delete(TOOL_STARTED_AT_KEY) || Time.current
        RubyLLMTelemetry.state.tool_spans << RubyLLMTelemetry.build_tool_span(payload, started_at, Time.current)
      rescue StandardError => e
        warn "[ActiveAgents::RubyLLMTelemetry] #{e.class}: #{e.message}"
      end
    end
  end
end
