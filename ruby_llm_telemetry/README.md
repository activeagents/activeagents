# active_agents-ruby_llm_telemetry

Reports [RubyLLM](https://github.com/crmne/ruby_llm) chats to an
ActiveAgents-compatible trace endpoint (`POST /v1/traces`) — the hosted
platform, or any self-hosted ActiveAgent dashboard.

For apps built directly on RubyLLM: no ActiveAgent framework dependency,
nothing beyond ActiveSupport and stdlib. Apps that can adopt
`ActiveAgent::Base` should use the framework's `ruby_llm` provider instead,
which reports telemetry on its own.

## Install

```ruby
# Gemfile
gem "active_agents-ruby_llm_telemetry",
    github: "activeagents/activeagents", glob: "ruby_llm_telemetry/*.gemspec"
```

## Use

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  config.instrumenter = ActiveSupport::Notifications # RubyLLM 1.x; 2.x wires this up in Rails
end

ActiveAgents::RubyLLMTelemetry.subscribe!(
  api_key: ENV["ACTIVEAGENTS_API_KEY"],
  endpoint: ENV.fetch("ACTIVEAGENTS_TELEMETRY_ENDPOINT", ActiveAgents::RubyLLMTelemetry::DEFAULT_ENDPOINT),
  service_name: "my-app",
  environment: Rails.env
)
```

The key is a platform API key (Settings → API Keys) or an account's legacy
`telemetry_api_key`. Delivery is fire-and-forget on a background thread, and
failures are warned and swallowed — telemetry never raises into the app.

## What a turn looks like

One trace per conversation turn: a single `root` span (`Agent.action`)
covering the whole provider loop, carrying `llm.rounds` and the turn's token
totals, with a `tool` span per tool call hanging off it with real timings.

There is no separate `llm` span — it spanned the identical window as the
root, so it only restated it under a less useful name.

RubyLLM emits a `chat.ruby_llm` event per provider round, and the two
generations arrange them differently — 1.x nests a tool round inside the
enclosing event, 2.x drives a flat `step until complete?` loop whose rounds
are siblings with tool calls between them. Rounds are accumulated and flushed
on the round that ends the turn, so both produce the same trace.

Prompts, completions, and tool arguments/results are not sent unless
`capture_content: true` is passed to `subscribe!`; error messages are always
truncated.

## Capturing prompts and completions

Off by default, since this traffic may carry sensitive data. Enabling it adds
`llm.prompt`, `llm.instructions` (every system message, joined — RubyLLM's
`with_instructions` appends), `llm.completion`, and each tool call's
`tool.arguments` / `tool.result` as span attributes, so a trace shows the
whole prompt → tool → result → response flow. Captured values are truncated
to `CONTENT_LIMIT` (4000) characters.

```ruby
subscribe!(api_key: ..., capture_content: true)
```

## Naming the traffic

RubyLLM carries no application identity on the payload — neither a
`RubyLLM::Agent` class nor an `acts_as_chat` record reaches the instrumenter
— so unattributed traffic reports as `RubyLLM::Chat`:

```ruby
# Per call site
ActiveAgents::RubyLLMTelemetry.with_agent("SupportBot", action: "respond") { chat.ask(...) }

# Or from the initializer, derived from the event payload
subscribe!(api_key: ..., agent_resolver: ->(payload) { { name: "SupportBot", action: payload[:tools].present? ? "respond" : "summarize" } })

# Or name every RubyLLM::Agent subclass by its class
module AgentTelemetryAttribution
  def ask(...) = ActiveAgents::RubyLLMTelemetry.with_agent(self.class.name) { super }
end
RubyLLM::Agent.prepend(AgentTelemetryAttribution)
```

## Scope

Chat completions and tool calls. RubyLLM's `embedding`, `image`,
`moderation`, `speech`, `transcription`, `request`, and `models.refresh`
events are not reported yet — they carry their own token counts and are a
natural extension of the same subscriber.

Concurrent tool execution runs tools off the instrumented thread and is not
captured; sequential execution (the default) is fully covered. A turn left
open by a halted tool call, or by an app driving 2.x's `step`/`run_tools` by
hand, is flushed when the next chat reports, after `MAX_TURN_SECONDS`, or on
an explicit `flush!`.

## Tests

```bash
cd ruby_llm_telemetry && bundle exec rake test
```
