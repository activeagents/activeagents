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

### The adapter

```ruby
# lib/active_agents/ruby_llm_telemetry.rb
# frozen_string_literal: true

require "net/http"
require "json"
require "securerandom"

module ActiveAgents
  # Reports RubyLLM chat completions to an ActiveAgents-compatible trace
  # endpoint (the same wire format ActiveAgent::Telemetry uses).
  #
  # Subscribes to RubyLLM's instrumentation events; requires
  # RubyLLM.config.instrumenter = ActiveSupport::Notifications.
  module RubyLLMTelemetry
    DEFAULT_ENDPOINT = "https://api.activeagents.ai/v1/traces"
    AGENT_KEY = :active_agents_ruby_llm_agent

    class << self
      attr_reader :endpoint, :api_key, :service_name, :environment

      def subscribe!(api_key:, endpoint: DEFAULT_ENDPOINT, service_name: nil, environment: nil)
        @api_key = api_key
        @endpoint = endpoint
        @service_name = service_name || (defined?(Rails) ? Rails.application.class.module_parent_name.underscore : "ruby_llm")
        @environment = environment || (defined?(Rails) ? Rails.env : ENV.fetch("RACK_ENV", "production"))

        ActiveSupport::Notifications.subscribe("chat.ruby_llm") do |event|
          report_chat_event(event)
        rescue StandardError => e
          warn "[ActiveAgents::RubyLLMTelemetry] #{e.class}: #{e.message}"
        end
      end

      # Attributes traces inside the block to a named agent/action.
      def with_agent(name, action: "chat")
        previous = Thread.current[AGENT_KEY]
        Thread.current[AGENT_KEY] = { name: name, action: action }
        yield
      ensure
        Thread.current[AGENT_KEY] = previous
      end

      private

      def report_chat_event(event)
        payload = event.payload
        response = payload[:response]
        return unless response # streaming interrupted or provider error

        agent = Thread.current[AGENT_KEY] || { name: "RubyLLM::Chat", action: "chat" }
        trace_id = SecureRandom.hex(16)
        root_id = SecureRandom.hex(8)
        started_at = Time.now - (event.duration / 1000.0)
        finished_at = Time.now
        error = payload[:exception_object]

        tokens = {
          "input" => response.respond_to?(:input_tokens) ? response.input_tokens.to_i : 0,
          "output" => response.respond_to?(:output_tokens) ? response.output_tokens.to_i : 0,
          "thinking" => 0
        }
        tokens["total"] = tokens.values.sum

        root_span = {
          "span_id" => root_id, "trace_id" => trace_id, "parent_span_id" => nil,
          "name" => "#{agent[:name]}.#{agent[:action]}", "type" => "root",
          "start_time" => started_at.utc.iso8601(6), "end_time" => finished_at.utc.iso8601(6),
          "duration_ms" => event.duration.round(2),
          "status" => error ? "ERROR" : "OK",
          "attributes" => {
            "agent.class" => agent[:name], "agent.action" => agent[:action],
            "agent.provider" => payload[:provider].to_s, "agent.model" => payload[:model].to_s
          }.merge(error ? { "error.type" => error.class.name, "error.message" => error.message } : {}),
          "tokens" => { "input" => 0, "output" => 0, "thinking" => 0, "total" => 0 },
          "events" => []
        }

        llm_span = root_span.merge(
          "span_id" => SecureRandom.hex(8), "parent_span_id" => root_id,
          "name" => "llm.generate", "type" => "llm",
          "attributes" => { "llm.provider" => payload[:provider].to_s, "llm.model" => payload[:model].to_s },
          "tokens" => tokens
        )

        post_traces(
          "traces" => [ {
            "trace_id" => trace_id,
            "service_name" => service_name,
            "environment" => environment,
            "timestamp" => finished_at.utc.iso8601(6),
            "resource_attributes" => {},
            "spans" => [ root_span, llm_span ]
          } ],
          "sdk" => { "name" => "active_agents-ruby_llm", "version" => "1.0", "language" => "ruby", "runtime_version" => RUBY_VERSION }
        )
      end

      def post_traces(body)
        uri = URI.parse(endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{api_key}"
        request.body = JSON.generate(body)

        Thread.new { http.request(request) }
      end
    end
  end
end
```

Notes:

- **Tokens** come straight from RubyLLM's response message
  (`input_tokens`/`output_tokens`); durations from the notification event.
- **Tool calls**: `tool_call.ruby_llm` events fire outside the chat event;
  a future version can correlate them into tool spans via the same
  thread-local. For now tool rounds appear as separate completions.
- **Failures** surface as `status: "ERROR"` traces with the exception
  attached, matching what the gem's own instrumentation emits.
- Requests are fire-and-forget on a background thread; batch buffering
  (like `ActiveAgent::Telemetry::Reporter`) is a natural upgrade if volume
  warrants it.

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
instead of a vendored file.
