# Agent Interactions: URL-Addressable Drill-Down

**Date:** 2026-07-30
**Branch:** `claude/analytics-api-key-encryption-9kwpsc`

## Summary

The per-agent conversation view (formerly "Conversation History") is now **Agent
Interactions**, lives at `/dashboard/agents/:id/interactions`, and every
drill-down level is reflected in the URL with breadcrumb links back up.

## URL Scheme

These are client-side routes, resolved against wherever the dashboard engine
is mounted — `/dashboard` on this platform, whatever the host app chose in a
self-hosted install. The engine's catch-all (`get "*path"`) renders the React
app for all of them, so deep links and reloads work.

| URL | View |
|-----|------|
| `/dashboard/agents/:id/interactions` | Agent Report — sessions list + cohorts by instructions × model |
| `/dashboard/agents/:id/interactions/runs/:runId` | A single run's interaction stream |
| `/dashboard/agents/:id/interactions/sessions` | Sessions list (persisted conversation contexts) |
| `/dashboard/agents/:id/interactions/sessions/:sessionId` | One session's full interaction stream |
| `/dashboard/agents/:id/history` | Legacy — normalized to `/interactions` via `history.replaceState` |
| `/dashboard/agents/:id/interactions/all` | Legacy — normalized to `/interactions/sessions` |

## Sessions Are Groupings

A "session" is a solid_agent `AgentContext`: one persisted conversation
stream per agent action (e.g. `DocsNavigatorAgent#ask`) that **every run
appends to** (`ActiveAgent::Dashboard::Api::InteractionsController`, served
at `/dashboard/api/interactions`). That's why an agent typically
shows a single session spanning many runs. Sessions are therefore a
top-level drill-down entry on the Agent Report ("Sessions — grouped
interaction streams"), alongside the instructions × model cohorts. The
detail-pane toggle formerly labeled "All interactions" is now "Sessions".

Session rows render the agent name with the action as its own chip
(`Docs Navigator #ask`) — activeagent lets developers define many actions
as prompts or tools, and each action gets its own stream, so the action is
first-class in the rendering (full `Agent#action` name in the tooltip).
Run cohorts label instructions with the agent version that introduced them
plus a digest-derived codename (`instructions v4 · zesty-vale`; hex sha in
the tooltip) via `Agent#instructions_digest_versions` and
`AgentRun#instructions_codename`.

Since sessions (and a drilled-in session) are a subset of one agent's
interactions, the sessions mode keeps the **agent scorecard** in view at the
top: avatar, agent name, and the Runs / Success / Avg Duration / Tokens
tiles, with a subtitle naming the drilled-in session when one is open. The
single-run header also names the agent ("Docs Navigator — Run #81").

## Behavior

- **Drilling in updates `window.location`** — selecting a run from the run list
  or from an expanded report cohort pushes `/interactions/runs/:runId`; the
  "Sessions" toggle pushes `/interactions/sessions`.
- **Deep links restore state** — a full page load on `/interactions/runs/81`
  fetches and renders Run #81; `popstate` (browser back/forward) re-applies
  whatever level the URL points at.
- **Breadcrumbs** in the detail pane mirror the URL:
  `{Agent name} / Interactions / Run #N` (or `Sessions`, then the session
  name when one is open). Agent name links back to the editor;
  "Interactions" clears the run selection and returns to the base URL.
- Duplicate history entries are avoided (`pushPath` no-ops when the path is
  already current).

## Files Changed

The React dashboard now lives in the activeagent gem at
`lib/active_agent/dashboard/frontend/`; paths below are relative to that.

- `components/dashboard/AgentInteractions.jsx` — renamed from
  `ConversationHistory.jsx`; URL sync (`pushPath`, `popstate` listener,
  deep-link parse on mount), breadcrumb bar, heading now "Agent Interactions".
- `pages/Dashboard.jsx` — routes `/agents/:id/interactions` (and legacy
  `/history`) to the view; the global `/interactions` check now excludes
  agent-scoped paths; `navigateTo('history')` pushes the new URL. Paths are
  built through `utils/dashboardPath.js` so they resolve against the mount.
- `components/dashboard/AgentEditor.jsx` — toolbar button label "History" →
  "Interactions".

The internal Dashboard view key remains `'history'`; only URLs, labels, and
the component name changed.

## Verified (Playwright, activeagents.orb.local)

1. `/dashboard/agents/50/history` → URL normalizes to `/interactions`.
2. Clicking a run → URL becomes `/interactions/runs/81`, breadcrumb shows
   `Docs Navigator / Interactions / Run #81`.
3. Browser back → returns to `/interactions`, report view restored.
4. Hard reload on `/interactions/runs/81` → run stream restored.
5. "Sessions" toggle → `/interactions/sessions`; breadcrumb "Interactions"
   link → back to base.

Screenshot: `tmp/playwright/agent-interactions-drilldown.png` (gitignored).
