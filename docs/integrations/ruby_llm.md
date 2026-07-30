# RubyLLM → ActiveAgents observability

Apps built directly on [RubyLLM](https://github.com/crmne/ruby_llm) — without
ActiveAgent — can still ship traces to the ActiveAgents platform (or a
self-hosted ActiveAgent dashboard). The ingest endpoint (`POST /v1/traces`)
speaks a plain JSON wire format, and RubyLLM ≥ 1.4 has a built-in
instrumentation bus that exposes everything a trace needs.

Two integration paths, in order of preference:

## Option 1: adopt ActiveAgent's RubyLLM provider

If you can wrap your calls in an agent class, ActiveAgent ships a `ruby_llm`
provider that drives RubyLLM under the hood — and you get telemetry, the
free local dashboard, and solid_agent conversation persistence with zero
extra code:

```ruby
class SupportAgent < ActiveAgent::Base
  generate_with :ruby_llm, model: "claude-sonnet-4-5"
end
```

```yaml
# config/active_agent.yml
production:
  ruby_llm:
    service: "RubyLLM"
telemetry:
  enabled: true
  endpoint: https://api.activeagents.ai/v1/traces
  api_key: <%= ENV["ACTIVEAGENTS_API_KEY"] %>
```

## Option 2: instrument RubyLLM directly (no ActiveAgent dependency)

RubyLLM emits `chat.ruby_llm` and `tool_call.ruby_llm` events through a
configurable instrumenter. Point it at `ActiveSupport::Notifications` and
subscribe with the adapter below — a single vendorable file with no
dependencies beyond ActiveSupport and stdlib.

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  config.instrumenter = ActiveSupport::Notifications
end

ActiveAgents::RubyLLMTelemetry.subscribe!(
  api_key: ENV["ACTIVEAGENTS_API_KEY"],
  service_name: "my-app"
)
```

Attribute traffic to a logical agent (otherwise it reports as
`RubyLLM::Chat`):

```ruby
ActiveAgents::RubyLLMTelemetry.with_agent("SupportBot", action: "respond") do
  chat = RubyLLM.chat(model: "gpt-4o")
  chat.ask("How do I reset my password?")
end
```

### How events map to spans

A chat that runs tools emits **nested** `chat.ruby_llm` events — each tool
round recurses through `RubyLLM::Chat#complete`, and the outer event's token
fields repeat the final round's counts. The adapter therefore builds **one
trace per outermost event**:

- a `root` span named `Agent.action`,
- a single `llm` span covering the whole provider loop (tools execute inside
  it — the same shape the dashboard's generation-vs-tools time breakdown
  expects), with token totals summed from the assistant messages the ask
  added, so nested rounds are not double counted, and
- a `tool` span per `tool_call.ruby_llm` event, with real start/end times
  and `tool.name` / `tool.call_id` attributes, parented under the llm span.

Tool arguments and results are deliberately never sent, and error messages
are truncated — safe defaults for apps whose tool traffic may contain
sensitive data.

### The adapter

```ruby
# lib/active_agents/ruby_llm_telemetry.rb
require "net/http"
require "json"
require "securerandom"

module ActiveAgents
  # Reports RubyLLM chat completions to an ActiveAgents-compatible trace
  # endpoint (POST /v1/traces — the wire format ActiveAgent::Telemetry uses).
  #
  # Requires RubyLLM.config.instrumenter = ActiveSupport::Notifications.
  module RubyLLMTelemetry
    DEFAULT_ENDPOINT = "https://api.activeagents.ai/v1/traces"
    AGENT_KEY = :active_agents_ruby_llm_agent
    STATE_KEY = :active_agents_ruby_llm_state
    TOOL_STARTED_AT_KEY = :_active_agents_started_at
    ERROR_MESSAGE_LIMIT = 200

    State = Struct.new(:depth, :started_at, :tool_spans, :rounds)

    class << self
      attr_reader :endpoint, :api_key, :service_name, :environment

      def subscribe!(api_key:, endpoint: DEFAULT_ENDPOINT, service_name: nil, environment: nil, async: true)
        @api_key = api_key
        @endpoint = endpoint
        @service_name = service_name || default_service_name
        @environment = environment || default_environment
        @async = async

        @subscriptions ||= [
          ActiveSupport::Notifications.subscribe("chat.ruby_llm", ChatSubscriber.new),
          ActiveSupport::Notifications.subscribe("tool_call.ruby_llm", ToolCallSubscriber.new)
        ]
      end

      def unsubscribe!
        Array(@subscriptions).each { |subscription| ActiveSupport::Notifications.unsubscribe(subscription) }
        @subscriptions = nil
      end

      # Attributes traces inside the block to a named agent/action; otherwise
      # traffic reports as RubyLLM::Chat. Safe to call when not subscribed.
      def with_agent(name, action: "chat")
        previous = Thread.current[AGENT_KEY]
        Thread.current[AGENT_KEY] = { name: name, action: action }
        yield
      ensure
        Thread.current[AGENT_KEY] = previous
      end

      def state
        Thread.current[STATE_KEY] ||= State.new(0, nil, [], 0)
      end

      def clear_state
        Thread.current[STATE_KEY] = nil
      end

      def report_chat(payload, started_at, finished_at, tool_spans:, rounds:)
        agent = Thread.current[AGENT_KEY] || { name: "RubyLLM::Chat", action: "chat" }
        trace_id = SecureRandom.hex(16)
        root_id = SecureRandom.hex(8)
        llm_id = SecureRandom.hex(8)
        error = payload[:exception_object]

        base = {
          "trace_id" => trace_id,
          "start_time" => started_at.utc.iso8601(6),
          "end_time" => finished_at.utc.iso8601(6),
          "duration_ms" => duration_ms(started_at, finished_at),
          "status" => error ? "ERROR" : "OK",
          "events" => []
        }

        root_attributes = {
          "agent.class" => agent[:name],
          "agent.action" => agent[:action],
          "agent.provider" => payload[:provider].to_s,
          "agent.model" => payload[:model].to_s
        }
        root_attributes.merge!(error_attributes(error)) if error

        root_span = base.merge(
          "span_id" => root_id, "parent_span_id" => nil,
          "name" => "#{agent[:name]}.#{agent[:action]}", "type" => "root",
          "attributes" => root_attributes,
          "tokens" => zero_tokens
        )

        llm_span = base.merge(
          "span_id" => llm_id, "parent_span_id" => root_id,
          "name" => "llm.generate", "type" => "llm",
          "attributes" => {
            "llm.provider" => payload[:provider].to_s,
            "llm.model" => payload[:model].to_s,
            "llm.rounds" => rounds,
            "llm.streaming" => payload[:streaming] || false
          },
          "tokens" => token_totals(payload)
        )

        child_tool_spans = tool_spans.map { |tool_span| tool_span.merge("trace_id" => trace_id, "parent_span_id" => llm_id) }

        post_traces(
          "traces" => [ {
            "trace_id" => trace_id,
            "service_name" => service_name,
            "environment" => environment,
            "timestamp" => finished_at.utc.iso8601(6),
            "resource_attributes" => {},
            "spans" => [ root_span, llm_span ] + child_tool_spans
          } ],
          "sdk" => { "name" => "active_agents-ruby_llm", "version" => "1.1", "language" => "ruby", "runtime_version" => RUBY_VERSION }
        )
      end

      def build_tool_span(payload, started_at, finished_at)
        error = payload[:exception_object]
        attributes = {
          "tool.name" => payload[:tool_name].to_s,
          "tool.call_id" => payload[:tool_call_id].to_s
        }
        attributes.merge!(error_attributes(error)) if error

        {
          "span_id" => SecureRandom.hex(8),
          "name" => "tool.#{payload[:tool_name]}",
          "type" => "tool",
          "start_time" => started_at.utc.iso8601(6),
          "end_time" => finished_at.utc.iso8601(6),
          "duration_ms" => duration_ms(started_at, finished_at),
          "status" => error ? "ERROR" : "OK",
          "attributes" => attributes,
          "tokens" => zero_tokens,
          "events" => []
        }
      end

      private

      def default_service_name
        defined?(Rails) ? Rails.application.class.module_parent_name.underscore : "ruby_llm"
      end

      def default_environment
        defined?(Rails) ? Rails.env : ENV.fetch("RACK_ENV", "production")
      end

      def duration_ms(started_at, finished_at)
        ((finished_at - started_at) * 1000).round(2)
      end

      def error_attributes(error)
        { "error.type" => error.class.name, "error.message" => error.message.to_s.truncate(ERROR_MESSAGE_LIMIT) }
      end

      def zero_tokens
        { "input" => 0, "output" => 0, "thinking" => 0, "total" => 0 }
      end

      def token_totals(payload)
        initial_count = Array(payload[:input_messages]).size
        new_messages = Array(payload[:messages_after])[initial_count..] || []
        assistant_messages = new_messages.select { |message| message.respond_to?(:role) && message.role.to_s == "assistant" }

        tokens = {
          "input" => sum_tokens(assistant_messages, :input_tokens),
          "output" => sum_tokens(assistant_messages, :output_tokens),
          "thinking" => sum_tokens(assistant_messages, :thinking_tokens)
        }
        tokens["total"] = tokens.values.sum
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
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{api_key}"
        request.body = JSON.generate(body)
        http.request(request)
      rescue StandardError => e
        warn "[ActiveAgents::RubyLLMTelemetry] #{e.class}: #{e.message}"
      end
    end

    # Evented ActiveSupport::Notifications subscriber; finish fires even when
    # the instrumented block raises, with the exception on the payload.
    class ChatSubscriber
      def start(_name, _id, _payload)
        state = RubyLLMTelemetry.state
        state.started_at = Time.current if state.depth.zero?
        state.depth += 1
      end

      def finish(_name, _id, payload)
        state = RubyLLMTelemetry.state
        state.rounds += 1
        state.depth -= 1
        return unless state.depth.zero?

        begin
          RubyLLMTelemetry.report_chat(payload, state.started_at, Time.current, tool_spans: state.tool_spans, rounds: state.rounds)
        rescue StandardError => e
          warn "[ActiveAgents::RubyLLMTelemetry] #{e.class}: #{e.message}"
        ensure
          RubyLLMTelemetry.clear_state
        end
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
```

Notes:

- **Tokens** are summed from the assistant messages added during the ask
  (`input_tokens`/`output_tokens`/`thinking_tokens` per message), which is
  the accurate per-round accounting; the event-level token fields on nested
  events double-report the final round.
- **Tool spans** carry real start/end times, so the dashboard's waterfall,
  generation-vs-tools breakdown, and slowest-operations views work for
  RubyLLM apps the same as for platform-executed agents. Concurrent tool
  execution (when enabled on the chat) runs tools off-thread and is not
  captured — sequential execution (the default) is fully covered.
- **Failures** surface as `status: "ERROR"` traces with the exception class
  and a truncated message attached.
- Requests are fire-and-forget on a background thread; pass `async: false`
  for deterministic delivery in tests, and stub `post_traces` to assert on
  the built payload. Batch buffering (like
  `ActiveAgent::Telemetry::Reporter`) is a natural upgrade if volume
  warrants it.

## Local / self-hosted dashboards

The endpoint is just a parameter — point it at any deployment of this app or
of the gem's dashboard:

```ruby
ActiveAgents::RubyLLMTelemetry.subscribe!(
  api_key: ENV["ACTIVEAGENTS_API_KEY"],
  endpoint: ENV.fetch("ACTIVEAGENTS_TELEMETRY_ENDPOINT", ActiveAgents::RubyLLMTelemetry::DEFAULT_ENDPOINT),
  service_name: "my-app",
  environment: Rails.env
)
```

For a dashboard running locally (e.g. via `docker-compose.dev.yml` under
OrbStack/Docker Desktop — see `docs/local-mac-llm.md`), set
`ACTIVEAGENTS_TELEMETRY_ENDPOINT=http://localhost:3000/v1/traces` (or the
container's `*.orb.local` hostname) in the reporting app. The Bearer token
is either a platform API key generated from Settings → API Keys (`aa_…`
keys, once PR
[#96](https://github.com/activeagents/activeagents/pull/96) lands) or the
account's legacy `telemetry_api_key` from the Organization page.

## Wire format reference

The endpoint accepts what `ActiveAgent::Telemetry::Reporter` sends —
`{ "traces": [...], "sdk": {...} }` with `Authorization: Bearer
<telemetry_api_key>` (find your key on the dashboard's Organization page).
Full payload spec: activeagent's `docs/framework/telemetry.md`
("self-hosting endpoint requirements"). Anything that speaks this format —
Python sidecars, edge functions, other frameworks — can feed the same
dashboard.

## Roadmap note

The right long-term home for this adapter is the activeagent gem itself
(e.g. `ActiveAgent::Telemetry::Adapters::RubyLLM`, loadable without the
rest of the framework) so RubyLLM users get a supported, versioned client
instead of a vendored file. First production consumer: Sparkle's Clara
admin chat (`combinaut/sparkle`, `lib/active_agents/ruby_llm_telemetry.rb`).
