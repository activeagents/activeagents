# Support Inbox — ActiveAgent example app

A small but real Rails app that shows the whole ActiveAgent product loop:

- **AI product features** built on the [activeagent](https://github.com/activeagents/activeagent) gem:
  - `TriageAgent` — classifies each ticket (category / priority / sentiment + one-line summary), parsed defensively from a JSON-shaped response
  - `SupportReplyAgent` — drafts replies grounded in matching knowledge-base articles (`config/knowledge_base.yml`), with the conversation persisted through [solid_agent](https://github.com/activeagents/solid_agent)
  - `SummarizeAgent` — running thread summaries
- **Support over email** — the same agents on a real transport: ActionMailbox
  receives, `SupportMailbox` answers, ActionMailer replies on the customer's
  thread. See [Email support](#email-support) below.
- **Monitoring**:
  - In development, traces land in the **actionagent dashboard** at [`/activeagents`](http://localhost:3000/activeagents)
  - In production (or whenever `ACTIVEAGENTS_API_KEY` is set), traces POST to the **ActiveAgents platform** — the same pipeline, hosted
  - Every persisted `AgentGeneration` carries the `trace_id` of the telemetry trace that produced it, so a conversation row here links to its trace on the dashboard

It works **without any API keys**: the gem's mock provider exercises the full
prompt → provider → response pipeline (including token accounting and
telemetry). Set `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` to use a real model.

This app doubles as the **runnable reference for the self-hosted
(enterprise) observability mode** — an existing Rails app that mounts
`ActiveAgent::Dashboard::Engine` and stores its own traces. The full
deployment story (production auth, ingest keys, fleet ingest, subdomain
mounts) is in the gem's `docs/framework/self-hosted-observability.md`.

## Run it locally

```bash
bundle install
bin/rails db:prepare db:seed
bin/rails server
```

Open http://localhost:3000, click into a ticket, and hit **Triage**,
**Draft reply**, or **Summarize thread**. Then open
http://localhost:3000/activeagents to see each click as a trace with a span
waterfall and token counts.

To post traces to a platform workspace instead (hosted or local):

```bash
ACTIVEAGENTS_API_KEY=<your workspace key from the Organization page> \
ACTIVEAGENTS_TELEMETRY_ENDPOINT=https://staging.activeagents.ai/v1/traces \
bin/rails server
```

## Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `AI_PROVIDER` | `mock`, `openai`, `anthropic`, or `openrouter` | auto: first provider with credentials, else `mock` |
| `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `OPENROUTER_API_KEY` | real model credentials | — |
| `ACTIVEAGENTS_API_KEY` | workspace telemetry key (Organization page) | — (dev falls back to the local dev console) |
| `ACTIVEAGENTS_TELEMETRY_ENDPOINT` | trace ingest URL | `https://api.activeagents.ai/v1/traces` |

## Deploy to staging

The platform repo's staging terraform can run this app as a public Cloud
Run service that posts telemetry to the staging platform:

1. Sign up on staging and copy the workspace API key from the Organization page.
2. In the GitHub repo settings set the **repository variable** `DEPLOY_DEMO_APP=true`
   and the **secret** `DEMO_ACTIVEAGENTS_API_KEY=<that key>`.
3. Run the *Deploy to Staging* workflow. The job summary prints the demo
   app's `run.app` URL (also `terraform output demo_app_url`).

Details: `terraform/modules/demo-app`. The service uses ephemeral SQLite
(re-seeded on every boot, max one instance) — it is a demo, not a place to
keep data. Agents default to the mock provider; set `demo_ai_provider` in
terraform (plus provider keys as env) for real models.

## Email support

A customer emails `support@example.com` and gets an answer from the agent on
the same thread. Nothing new is asked of the agents — `SupportMailbox` runs
the same `TriageAgent` the Triage button runs, and `SupportReplyAgent#respond`
continues the same solid_agent conversation the Draft reply button writes
into, so an emailed ticket and a clicked one are the same conversation with
different doors.

```
inbound email ─▶ ApplicationMailbox ─▶ SupportMailbox ─▶ SupportReplyAgent ─▶ SupportMailer ─▶ reply
                                          │                    │
                                     Ticket + Reply      AgentContext + trace
```

### Try it without a mail server

```bash
bin/rails server
open http://localhost:3000/rails/conductor/action_mailbox/inbound_emails/new
```

Paste an email from `dana@example.com` to `support@example.com`, deliver it,
and the inbox has a new ticket: triaged, answered, and with the outgoing
reply recorded on the thread. Replies come back to
`support+<ticket token>@example.com`, which is how the next message finds its
ticket. In development `config.action_mailer.delivery_method` is `:test`, so
nothing leaves your machine; in production, point an SMTP relay (or Postmark,
Mailgun, SendGrid, Mandrill) at the ingress — see
`config/environments/production.rb`.

### What the transport layer handles

`lib/action_mail_agent/` is deliberately app-agnostic — it knows about email,
conversations and agents, and nothing about tickets. It is the part every
email/agent integration ends up rebuilding:

| | |
|---|---|
| `BodyParser` | Reduces a reply chain to what the customer wrote this time — Gmail/Outlook/Apple quoting, forwarded-message separators, signatures, HTML-only mail |
| `Addressing` | The `support+<token>@` reply addresses conversations thread on, lowercase so they survive a round trip |
| `InboundMessage` | One normalized view of a `Mail::Message`: sender, subject, thread ids, and the header tells that say a machine sent it |
| `LoopGuard` | Refuses to answer bounces, vacation responders, mailing lists, our own addresses, and a conversation that has burst past its reply rate |
| `Mailbox` | The exchange itself: parse, guard, record, answer, reply — with hooks an app fills in (`app/mailboxes/support_mailbox.rb` is 130 lines of ticket-specific code) |

Threading works two ways, because one is not enough: the `+tag` on the reply
address survives clients that rewrite headers, and the `References`/
`In-Reply-To` chain catches replies sent to the plain support address.

Rolling this out in front of real customers starts at
`SUPPORT_DELIVERY_MODE=draft`: the agent's replies are generated and recorded
for a human to read, and nothing is sent.

## Tests

```bash
bin/rails test
```

40 tests, all against the mock provider: the three agent features with
solid_agent persistence and trace correlation, the send-draft flow, the
email exchange end to end (threading, quote stripping, loop refusals,
handoff, duplicate delivery), and unit coverage of the transport layer.

## Notes

- The `Gemfile` tracks the gems' `main` branches (pin released versions
  once activeagent v2 ships).
