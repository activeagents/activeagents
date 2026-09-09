# Code Agent Sessions (operator runbook)

## Overview

Code Sessions let a dashboard user hand one of their agents, together with a
brief compiled from its evaluations and production metrics, to a sandboxed
coding agent (Claude Code, Codex CLI, GitHub Copilot CLI, opencode, pi, omp,
aider). The coding agent runs inside a [code-on-incus](https://github.com/mensfeld/code-on-incus)
(`coi`) container on the platform's Incus host, clones the user's repository
with a token they supplied, and works through the brief.

The feature lives in the `actionagent` engine (the dashboard gem). This app
supplies the pieces a hosted product has and a self-hosted install does not:
the Incus host, SSH plumbing, per-account GitHub tokens, and plan quotas. The
engine's own reference is `docs/framework/code-sessions.md` in the
activeagent repository; this page is about running it here.

```
Dashboard user                Rails app (Cloud Run)            Incus host
+---------------+   HTTPS    +-----------------------+  SSH   +----------------------------+
| Code Sessions | ---------> | ActionAgent engine    | -----> | coi (code-on-incus)        |
| /code/new     |            |  CodeSession model    |        |  +----------------------+  |
|               |            |  CodeSessionBrief     |        |  | incus container      |  |
|               |            |  CodeOnIncusBackend   |        |  |  claude / codex /... |  |
|               |            |  Provision/Run jobs   |        |  |  /workspace/repo     |  |
+---------------+            +-----------------------+        |  |  /brief/BRIEF.md     |  |
                                       |                      |  +----------------------+  |
                                       v                      |  nftables allowlist        |
                             ProviderKey(provider: "github")  |  threat monitoring         |
                             per account, encrypted           +----------------------------+
```

## What the engine expects from this host

| Seam | Where it is set | Notes |
|------|-----------------|-------|
| `ActionAgent.code_session_backend` | `config/initializers/action_agent_code_sessions.rb` | `code_on_incus` by default; `mock` for review apps without a host |
| `ActionAgent.code_on_incus.ssh_target` | same, from `COI_SSH_TARGET` | `user@host`; unset means coi runs on the app box |
| `ActionAgent.code_on_incus.state_dir` | same, from `COI_STATE_DIR` | per-session state on the coi host |
| `ActionAgent.github_token_resolver` | same | reads the account's `github` ProviderKey |
| `ActionAgent.provider_credentials_resolver` | PR #105's `config/initializers/action_agent.rb` | supplies the coding tool's own API key (Anthropic, OpenAI, OpenRouter) from the account's provider keys |
| `ActionAgent.quota_checker` / `usage_recorder` | same | every `run` counts as one agent execution against the plan |

The initializer is inert until the engine is in the bundle (it checks
`ActionAgent.respond_to?(:code_session_backend)`), so it is safe on `main`
before the engine mount from PR #105 lands.

## Setting up the Incus host

`scripts/setup-incus-host.sh` does all of this; the `install_code_on_incus`
step is on by default and can be skipped with `INSTALL_COI=false`.

1. Provision a Linux host (Ubuntu 22.04+ or Debian 12+) with at least 4 vCPU
   and 16 GB RAM. Each session container is capped at 4 CPUs and 8 GB by the
   engine's default `[limits]`, so size the host for the number of parallel
   sessions you expect (`max_sessions_per_owner` is 5 per account).
2. Run the setup script as root. It installs Incus, then:
   - installs `coi` with the upstream installer
     (`curl -fsSL https://raw.githubusercontent.com/mensfeld/code-on-incus/master/install.sh | bash`);
     an existing binary is left alone so re-running the script never upgrades
     behind your back;
   - runs `coi build` (5-10 minutes) unless `coi health` already passes;
     `COI_REBUILD=true` forces a rebuild after an upstream image change;
   - runs `coi health` and fails the script if it does not pass.
3. Create the SSH user the Rails app will use (or reuse the deploy user), add
   it to `incus-admin`, install the app's deploy public key, and confirm
   `ssh -o BatchMode=yes user@host coi health` works from the app's network
   without a prompt. The engine runs every command with `BatchMode=yes` and
   `ConnectTimeout=10`; anything interactive fails the session.
4. Optionally create `COI_STATE_DIR` (for example
   `/var/lib/activeagents/code-sessions`) owned by that user, mode 0700. The
   engine creates one subdirectory per session there and removes it at
   terminate.

Re-running the script is safe: every step checks for what it would create.

### Base profile

The engine writes one coi profile per session that `inherits = "hardened"`.
`hardened` is coi's own restrictive base profile, so there is nothing to
create on the host; if you want platform-wide changes (an extra allowlisted
host, a different image), define a profile in `~/.coi/profiles/` on the coi
host and set `ActionAgent.code_on_incus.base_profile` in the initializer.

## Environment variables (Rails app)

```bash
CODE_SESSION_BACKEND=code_on_incus      # or mock for review apps
COI_SSH_TARGET=coi@sandbox-host.example.com
COI_STATE_DIR=/var/lib/activeagents/code-sessions   # optional
```

There is no `GITHUB_TOKEN` variable to set. In multi-tenant mode the engine
refuses to fall back to a platform-wide token; every session uses the
account's own token or none at all.

## GitHub access

Users add a GitHub personal access token under Settings -> Provider API Keys
-> "GitHub (code sessions)". It is a `ProviderKey` with `provider: "github"`,
encrypted at rest with Active Record Encryption and shown back only as a
masked hint, exactly like the LLM keys. Recommend fine-grained tokens scoped
to the repositories a session will touch:

- `read` sessions need Contents: read;
- `write` sessions need Contents: read and write plus Pull requests: read and
  write so the coding agent can push a branch and open a PR.

How the token travels: the engine resolves it through
`ActionAgent.github_token_resolver` at provision time, writes it to
`<state_dir>/<session>/secrets/github_token` (0600) over SSH via stdin (never
in argv), and the coi profile exposes it inside the container through
`[env_commands]` as `GH_TOKEN` / `GITHUB_TOKEN`. The token is never stored on
the `code_sessions` row, never logged (`github_token` is a filtered
parameter), and the file is deleted when the session is terminated or expires.
Transcripts are masked before they are saved.

## Quotas and limits

| Limit | Value | Enforced by |
|-------|-------|-------------|
| Active sessions per account | 5 (`code_session_limits[:max_sessions_per_owner]`) | engine, 422 on create |
| Session lifetime | 4 hours (`session_duration_minutes`) | engine, `CodeSessionCleanupJob.expire_stale!` |
| One run | 60 minutes (`run_timeout_seconds`) | engine watchdog kills the coi process group |
| Container | 4 CPUs, 8 GB (`code_on_incus.cpu_limit` / `memory_limit`) | coi `[limits]` |
| Plan quota | one agent execution per `run` | `quota_checker` / `usage_recorder` from PR #105 |

Schedule `ActionAgent::CodeSessionCleanupJob.expire_stale!` alongside the
existing sandbox cleanup (Solid Queue recurring task) so abandoned sessions
release their containers and secret files.

## Network modes

| Mode | Meaning | Use |
|------|---------|-----|
| `restricted` | coi's hardened default; only the hosts coi needs plus the engine's allowlist (GitHub, rubygems, npm, PyPI, the LLM APIs) | default |
| `allowlist` | the engine's allowlist only, DNS pinned | when a repo needs one more registry, add it to `code_on_incus.allowlist` |
| `open` | no egress filtering | avoid on the shared host; leave to self-hosters |

coi's threat monitoring is on for every session (`auto_pause_on = "HIGH"`,
`auto_kill_on = "CRITICAL"`) and workspace secret masking is enabled.

## Operating

- Health: `GET /api/code_sessions` reports `backend.healthy`, which is
  `coi health` over SSH cached for a minute. If it is false, run the same
  command by hand as the app's SSH user.
- Inspecting a session: `ssh user@host` then
  `COI_CONFIG=<state_dir>/<session_id>/profile/config.toml coi attach`
  (the dashboard's Attach button copies this command for the user, who
  needs their own SSH access to use it).
- Stuck containers: `coi list --all` on the host; `coi kill` with the
  session's `COI_CONFIG`. Deleting the session from the dashboard runs
  shutdown, kill and `rm -rf` of the state directory.
- Logs: provisioning and run failures land on the session
  (`error_message`, events) with the token masked; the Rails log carries the
  same text plus the coi exit code.

## Non-goals

- No interactive terminal in the browser; attach is a copied SSH command.
- No GitHub App or OAuth flow; tokens are pasted by the user.
- No cost metering beyond what the coding tool prints in its transcript.

## Files

```
config/initializers/action_agent_code_sessions.rb   # backend, SSH target, token resolver
app/models/provider_key.rb                          # "github" provider
app/javascript/components/dashboard/SettingsView.jsx# "GitHub (code sessions)" entry
scripts/setup-incus-host.sh                         # install_code_on_incus step
```
