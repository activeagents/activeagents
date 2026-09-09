# `activeagent-telemetry` — a standalone gem for reporting traces

Status: proposal, 2026-07-30. Follows the local validation in
[rubyllm-telemetry-local-validation.md](rubyllm-telemetry-local-validation.md).

**Decision: ship a single standalone RubyGem, published under the
`activeagents` GitHub org and the same RubyGems owner as `activeagent`.** Not a
subpath of the `activeagent` gem, not a vendored file.

## Why standalone

The consumer is an app that already has its own LLM stack — RubyLLM, or
anything else — and wants to ship traces to an ActiveAgents dashboard. It will
never subclass `ActiveAgent::Base`. Making it take `gem "activeagent"` means
taking **actionpack, actionview, activemodel, and activejob** for a ~300-line
trace shipper: the runtime dependencies weigh more than the thing being
installed. That is the reason this got hand-vendored into the client app in the first
place, and a subpath require would not have fixed it — it avoids the *load*
cost, not the *install* cost.

A standalone gem also gives the integration story a name to point at. "Add
`activeagent-telemetry` to your Gemfile" is a one-line pitch to a team running
someone else's framework; "add our full Rails agent framework, then require one
file out of it" is not.

## Naming

| | |
|---|---|
| Gem | `activeagent-telemetry` |
| Repo | `github.com/activeagents/activeagent-telemetry` |
| Namespace | `ActiveAgent::Telemetry` (+ `::Adapters::RubyLLM`) |
| License / owner | MIT, same author + `rubygems_mfa_required` as `activeagent` |

Verified 2026-07-30: `activeagent-telemetry` is unclaimed on RubyGems (404), as
are `active_agent-telemetry`, `activeagents-telemetry`, and
`activeagent_telemetry`. `activeagent` itself is published at 1.0.3 (~123k
downloads), so the hyphenated name reads as its companion — the conventional
Ruby signal for exactly this relationship.

Keeping the `ActiveAgent::Telemetry` namespace matters: the code moves out of
the framework gem, so the constant path should stay put and an app loading both
gems must see one coherent namespace, not two.

**Hazard to handle deliberately.** `activeagent` declares `autoload :Telemetry`
(`lib/active_agent.rb:109`) resolving to its *own* `active_agent/telemetry.rb`.
With both gems installed and the framework gem still carrying its copy,
whichever appears first on `$LOAD_PATH` wins — a silent, load-order-dependent
split brain. Two ways out, in order of preference: (a) do step 8 promptly, so
`activeagent` depends on the new gem and deletes its copy, leaving exactly one
definition; or (b) until then, have the new gem define the constant only if not
already defined, and log loudly when it detects the framework's version. Do not
leave both copies live and unguarded.

## What goes in it

Lifted from `activeagent/lib/active_agent/telemetry/`:

- `telemetry.rb` — module entry, `Telemetry.configure`, `.trace`, `.span`,
  `.flush`, `.shutdown`, `NullSpan`
- `telemetry/configuration.rb` — endpoint, api_key, sampling, batching, service
  name/environment resolution
- `telemetry/span.rb` — span tree, tokens, status, `#to_h`
- `telemetry/reporter.rb` — buffering + batched background HTTP delivery
- `telemetry/tracer.rb` — trace envelope assembly

Plus the new adapter, ported from the client app's vendored file:

- `telemetry/adapters/ruby_llm.rb` — `ActiveAgent::Telemetry::Adapters::RubyLLM`

This is a clean cut, verified rather than assumed: those five files load with
**no Rails and no `ActiveAgent::Base`**. `reporter.rb` requires only `net/http`,
`json`, `uri`; the rest require nothing. Confirmed by loading them against a
bare `$LOAD_PATH` — zero heavy features loaded, `ActiveAgent::Base` undefined.

Runtime dependency: **`activesupport` only** (`Span` uses `Time.current`,
`Configuration` uses `.present?`, and the RubyLLM adapter needs
`ActiveSupport::Notifications` regardless). `ruby_llm` stays a *development*
dependency — the adapter should duck-type the notification payloads and never
reference a `::RubyLLM` constant, so the gem installs cleanly for non-RubyLLM
consumers.

### Two things that must be fixed in the cut

1. **`Reporter#store_traces_locally`** (reporter.rb:148) references
   `ActiveAgent::TelemetryTrace`, an ActiveRecord model in the dashboard engine.
   It is only reached when `local_storage = true`, but it cannot ship in a gem
   that doesn't depend on ActiveRecord. Either drop `local_storage` from the
   standalone gem, or resolve the constant lazily and document it as
   "only if the host app defines it."
2. **`ActiveAgent::VERSION`** is referenced by `Reporter` (line 120/128) and
   `Tracer#default_attributes` (line 179). The new gem needs its own
   `ActiveAgent::Telemetry::VERSION` and must not assume the framework's
   constant exists.

## Relationship to the `activeagent` gem

`activeagent` should **depend on `activeagent-telemetry`** and delete its own
copy, rather than the two carrying duplicate span/reporter code that drifts.
Its `telemetry/instrumentation.rb` — the `ActiveSupport::Concern` that prepends
`process_prompt`/`process_embed` on `ActiveAgent::Base` — **stays in
`activeagent`**, since it is framework-specific by definition. The split is:

- **`activeagent-telemetry`**: what a span is, how it is reported, adapters for
  other people's libraries.
- **`activeagent`**: how *this framework's* agent runs become spans.

This is not an optional follow-up. While both gems define
`ActiveAgent::Telemetry`, the constant an app gets depends on load order (see
the hazard above). The new gem can ship first — the client app doesn't install
`activeagent` at all, so it is unaffected — but converging the two should land
before any app is asked to run both.

## API

Mirror what the client app already runs in production shape:

```ruby
ActiveAgent::Telemetry::Adapters::RubyLLM.subscribe!(
  api_key:         ENV["ACTIVEAGENTS_API_KEY"],
  endpoint:        ENV.fetch("ACTIVEAGENTS_TELEMETRY_ENDPOINT", DEFAULT_ENDPOINT),
  service_name:    "my-app",
  environment:     Rails.env,
  agent_resolver:  ->(payload) { { name: "Assistant", action: ... } },
  capture_content: false
)
ActiveAgent::Telemetry::Adapters::RubyLLM.unsubscribe!
ActiveAgent::Telemetry::Adapters::RubyLLM.with_agent("Assistant", action: "respond") { ... }
```

Requires `RubyLLM.config.instrumenter = ActiveSupport::Notifications`.

### What the adapter reuses vs. keeps

**Reuses** `Reporter` (batching, background flush, endpoint/key config — note it
does *not* retry; it rescues and logs, same as the vendored file), `Configuration`
(every knob the vendored file re-declares, including `DEFAULT_ENDPOINT` and the
service-name fallback), and `Span` (replaces hand-built hashes; `#set_tokens`
computes `total`, and `#to_h` already matches the wire format).

**Keeps** the RubyLLM-specific logic that was hard-won:
- one trace per *outermost* `chat.ruby_llm` event (tool rounds recurse);
- token totals summed from the assistant messages the ask added, so nested
  rounds are not double counted;
- the evented `start`/`finish` subscribers — `Tracer#trace`'s block form cannot
  wrap a call inside someone else's library;
- `with_agent` / `agent_resolver` attribution;
- `capture_content` and its truncation.

### Two gaps to close during the move

1. **`Tracer#build_trace_payload` and `#flatten_spans` are private**
   (tracer.rb:108 precedes both), so an adapter must duplicate ~15 lines of
   envelope assembly. Add a public `Tracer#report_span_tree(root_span)`. Every
   future adapter needs it.
2. **`Configuration#capture_bodies` and `#redact_attributes` are declared but
   never read** — no consumer exists outside configuration.rb. They are
   aspirational knobs, not a feature. `capture_content` is the first real
   implementation of that idea; reconcile the names here rather than shipping
   both.

Also: `sdk.name` is hardcoded `"activeagent"` (reporter.rb:127). The new gem
should make it configurable and default to `activeagent-telemetry`, so the
ingest side can tell reported traffic apart — while confirming the hosted
endpoint accepts the new value before changing it.

## No overlap with the existing RubyLLM provider

`activeagent/lib/active_agent/providers/ruby_llm_provider.rb` deliberately calls
RubyLLM's *provider* layer (`@ruby_llm_provider.complete(...)`, lines 70/76)
rather than `RubyLLM::Chat`, to avoid fighting ActiveAgent's own tool loop.
RubyLLM emits `chat.ruby_llm` from `Chat#complete` — so the provider never fires
the events this adapter subscribes to. Disjoint paths: no double-counting, and
equally no way to reuse the provider's telemetry for raw-RubyLLM users. The
adapter is not redundant with it.

## Work

1. **Create `github.com/activeagents/activeagent-telemetry`**; gemspec modeled
   on `activeagent.gemspec` (MIT, `jusbowen@gmail.com`, homepage
   `activeagents.ai`, `rubygems_mfa_required`), one runtime dep on
   `activesupport`, `ruby_llm` in development only.
2. **Move the five telemetry files**, fix the two leaks above (`local_storage`
   AR reference, `ActiveAgent::VERSION`), add `Telemetry::VERSION`.
3. **Port the adapter** from the client app's `lib/active_agents/ruby_llm_telemetry.rb`,
   swapping hand-built hashes for `Span` and Net::HTTP for `Reporter`.
4. **Port the spec** (the client app's is 211 lines / 11 examples and now actually
   runs). Note the gem has **no telemetry tests at all** today, so this is the
   first. Prefer WebMock `stub_request`/`assert_requested` over VCR — you are
   asserting outbound shape, not replaying a third party. Watch the timing
   hazard: `Reporter#flush_buffer` spawns an unjoined delivery thread per flush
   (reporter.rb:97), so tests need a synchronous seam; `Telemetry.shutdown`
   joins only the *flush* thread. Keep the suite dependency-free — no dummy
   Rails app, which is friction the framework gem's `test_helper.rb` carries.
5. **Add a load-isolation test** asserting the gem requires with no Rails and no
   `ActiveAgent::Base`. That guarantee is the entire premise and will rot
   silently without a test.
6. **Publish 0.1.0**, then replace the client app's vendored file with the gem and keep
   its initializer.
7. **Rewrite** activeagents `docs/integrations/ruby_llm.md` Option 2 to point at
   the gem instead of inlining a copy that has already drifted (the documented
   copy predates `agent_resolver` and `capture_content`).
8. **Follow-up**: make `activeagent` depend on the new gem and delete its
   duplicate telemetry, keeping `instrumentation.rb`.

Sequencing note: the client app keeps its vendored copy until the gem is published and
verified against the same local stack, so there is never a window where neither
copy is authoritative.
