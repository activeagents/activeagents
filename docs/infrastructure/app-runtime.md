# Checkout sandboxes on Incus: the app-runtime image

An `app_runtime` sandbox boots a checkout of one of a workspace's GitHub
repositories so agents can use the app's own MCP tools. On the platform,
`IncusSandboxService` boots it in a container launched from the
`sandbox-app-runtime` image. This page covers that image, its boot command,
how the service drives it, and how to switch checkouts on in an environment.

## Building the image

The image is defined in `docker/sandbox/app-runtime/`:

| File | Purpose |
| --- | --- |
| `provision.sh` | Installs everything below into a fresh Ubuntu 24.04 container |
| `sandbox-app-boot` | The boot command, installed as `/usr/local/bin/sandbox-app-boot` |
| `services/start-*` | Starts PostgreSQL, MySQL or Redis on demand |

On an Incus host, one command builds the image or rebuilds it in place. Run it
as root from a checkout of this repository:

```bash
sudo scripts/build-app-runtime-image.sh
```

It launches a builder container, runs `provision.sh`, and publishes the result
under the alias `sandbox-app-runtime` in the `agent-sandboxes` project. The
image property `boot_spec_version` records the version of the boot spec its
`sandbox-app-boot` runs. Containers that are already running keep their own
copy, and the previous image is deleted once the new one holds the alias. The
script also reinstalls the sandbox reaper (see [Lifetime](#lifetime)), because
the Terraform startup script runs only when the host VM is created.

`scripts/setup-incus-host.sh` calls the same script on a new host.

To try the image locally, build the Docker target that runs the same
provisioning:

```bash
docker build --target app-runtime -t sandbox-app-runtime -f docker/sandbox/Dockerfile .
```

### What the image carries

- git, a C toolchain, and the headers that native gems build against
- mise, with the latest Ruby of 3.2, 3.3 and 3.4 preinstalled. A checkout that
  pins another version gets it installed when it boots, prebuilt where mise has
  a build for it.
- Node 22, with Yarn and pnpm through corepack, and Bun
- PostgreSQL, MySQL, Redis, SQLite and libvips. The servers are installed
  stopped, and a boot starts only those the checkout uses.
- socat, which forwards the container's port 8080 to the app
- the unprivileged user `sandbox` (uid 1000), which runs every command of the
  checkout
- Claude Code, installed for the user `claude` (uid 1001), and
  `sandbox-claude`, which runs it for the platform (see
  [Claude Code in a checkout](#claude-code-in-a-checkout))

### The workspace

| Path | Owner | Holds |
| --- | --- | --- |
| `/workspace` | root | nothing of its own |
| `/workspace/app` | `sandbox` | the checkout |
| `/workspace/boot` | root, `0700` | `spec.json`, `state.json` and `logs/` |
| `/workspace/run` | `sandbox` | `runtime.json`, the manifest the app writes |
| `/workspace/db` | `sandbox` | SQLite databases, when the checkout uses SQLite |

The image creates `/workspace` and `/workspace/app`. The service creates
`/workspace/boot`, and `sandbox-app-boot` creates the last two for the
`sandbox` user. `/workspace` belongs to root so that the checkout's code
cannot rename `/workspace/boot` and put a spec and state of its own in its
place, which a resume would then run as root. Run as root, `sandbox-app-boot`
refuses a spec that it, its directory or any directory above them would let
another user write or replace, and it never follows a symlink the app left
in `/workspace/run`.

There is no browser in the image. Browser sessions run in a container of their
own.

## How a checkout boots

1. **Fetch.** The service fetches the repository into `/workspace/app` as the
   `sandbox` user. The token reaches git through `GIT_CONFIG_*` in the fetch's
   exec environment. It never appears in argv or in `.git/config`.
2. **Resolve.** The service reads the checkout files that decide the boot
   (`Gemfile.lock`, `.activeagents/sandbox.yml`, `.ruby-version`,
   `.tool-versions`, `.node-version`, `.nvmrc`, `config/database.yml`,
   `config/application.rb`) through the instance file API. It then resolves
   them into a boot spec (`IncusSandboxService::BootSpec`), deciding everything
   the engine's local backend decides:
   - whether the engine's boot spec applies at all
   - the preflight: a `Gemfile.lock`, Ruby 3.2 and railties 7.2 or later, and
     `config/application.rb` at the root
   - which steps are skipped because the checkout already locks their gem
   - the sandbox's own database URLs, from the engine's `LocalSandboxDatabases`
   - the servers that the database and Redis URLs need in the container,
     whether the database plan, the spec's env or `sandbox.yml`'s env set
     them, and Redis when the bundle uses it. A URL naming another host gets
     no server.
   - the Ruby and Node versions the checkout pins

   Without an engine spec, the checkout boots as its `.activeagents/sandbox.yml`
   says, using the engine's defaults for anything the file leaves out.
3. **Run.** The service writes the spec to `/workspace/boot/spec.json` and runs
   `sandbox-app-boot --spec /workspace/boot/spec.json`. The script runs the
   toolchain step, then each step in order with its own timeout and its own
   log, then the manifest command. It then starts the app detached on
   `127.0.0.1:3000` and forwards the container's `:8080` to it. The script
   decides nothing about the repository itself, so a hosted boot and a local
   one cannot drift apart.
4. **Ready.** The app is ready once the MCP path named in the manifest answers
   405, 401 or 200 and the spec's `start_url` answers below 500. The script
   checks this inside the container. The service then checks the MCP path again
   on the container's address, which is where agents reach it.

### The boot spec

`spec.json` is version `IncusSandboxService::BOOT_SPEC_VERSION` (currently
1), and `sandbox-app-boot` refuses any other version. Its keys:

| Key | Meaning |
| --- | --- |
| `version` | the spec format version |
| `mode`, `kind` | `"spec"` (the engine's spec applied, `kind` bootstrap or custom) or `"config"` (sandbox.yml) |
| `app_dir`, `manifest_path` | `/workspace/app`, `/workspace/run/runtime.json` |
| `user` | `sandbox` |
| `port`, `listen_port` | `3000` for the app, `8080` forwarded to it |
| `timeout` | seconds for the steps, manifest and start together |
| `toolchain` | `{ ruby, node, services, timeout }`. `null` versions mean the image's defaults. |
| `directories` | directories created for the user first: `/workspace/run`, and `/workspace/db` for SQLite |
| `env` | environment for every command: database URLs, then the spec's own env |
| `secret_names` | variables whose values arrive only in the boot's exec environment |
| `steps` | `[{ name, command, timeout, skip, if_task }]`. `skip` carries a reason decided in advance. `if_task` skips the step when `bin/rails -T -A` lists no such task. |
| `manifest`, `start` | `{ command, timeout }` |
| `start_url` | a path that must answer below 500, or `null` |
| `keep_on_failure` | keep the container after a failed boot so it can be resumed |
| `recorded_steps` | the service's own steps so far (checkout, preflight), for progress |
| `facts` | what the service decided from the checkout, kept so a resume decides it the same way |

### State, logs and resuming

`sandbox-app-boot` keeps its state in `/workspace/boot/state.json`, which only
root can read. The state records each step with its status, timings and
detail, along with the failed step, whether the boot is kept, and the steps a
resume may start from. Each step writes its own log, `/workspace/boot/logs/<step>.log`.
The script masks the secrets' values, and their URL-encoded and Base64 forms,
in those logs and in every message it prints. `start.log` is the server's own
output and outlives the script, so the service masks it when it reads it.

`IncusSandboxService#boot_status` and `#boot_log` read the state and logs
through the file API, in the shapes the engine's
`SandboxOrchestrator#boot_status` and `#boot_log` document, masked of the
session's secrets. The service reads the state and the spec only while root
owns them. `#boot_log` fetches one page at a time with a Range request, so a
log of any size can be paged, including `start.log`, which grows for as long
as the server runs.

When a boot fails and its spec has `keep_on_failure`, the container stays.
`IncusSandboxService#resume_boot(session, from:, boot_config:)` then runs
`sandbox-app-boot --from <step>`, by default from the step that failed. The
fetch and the steps before that one are not run again. The toolchain step
always runs again, because it starts the database servers. Secret values are
never written down, so a boot whose spec had secrets needs the spec passed
again to resume.

### Environment and secrets

- The spec's secrets reach the container only as the boot's exec environment.
  They never appear in the instance config, in a file or in argv. Every
  command of the checkout inherits them.
- An app_runtime container carries none of the platform's `environment.*`
  keys. Its `RAILS_ENV` is whatever the spec's env says, and development
  otherwise.
- The boot gets no Claude Code or Codex credential.

## Claude Code in a checkout

`IncusSandboxService::ClaudeCode` gives the engine's optional orchestrator
verbs on Incus: Claude Code sessions (`run_code_session`,
`cancel_code_session`), the restart that verifies an evaluation fix
(`refresh_runtime`), and the four sign-in verbs of
`claude_code_auth = :sandbox_login` (activeagent#578). The engine's
*Implement with Claude Code* and its sign-in flow then work on Incus as they
do on the engine's local backend.

Everything goes through `/usr/local/bin/sandbox-claude`, which the platform
runs as root through the exec API:

| Command | What it does |
| --- | --- |
| `session-start --dir DIR` | Runs Claude Code headless on the request and prompt the platform wrote to `DIR`, detached |
| `session-cancel --dir DIR` | Stops that session: SIGTERM, then SIGKILL after a grace |
| `login-start` | Starts the unmodified `claude auth login` under a PTY |
| `login-code` | Hands the one-time code, from its own exec environment, to the waiting CLI once |
| `login-status` | The flow's state, or whether the CLI is logged in with a Claude subscription |
| `logout` | `claude auth logout` (which revokes the login), then removes its configuration |

- **Who runs Claude Code.** The image's `claude` user (uid 1001), never
  `sandbox`, which the checkout's processes run as. Its home, with the CLI's
  configuration and a subscription login, is `0700`, so the app cannot read
  it. `claude` is in the `sandbox` group; before each session the checkout is
  made group-writable, as `sandbox` (so a symlink the checkout plants changes
  nothing else), and the session works with umask `002`.
- **Sessions.** Each session gets `/workspace/claude/sessions/<id>/`, root's
  and `0700`. The prompt reaches the CLI on stdin and is deleted once open.
  The stream-json goes to `events.jsonl`, which the platform reads back with
  Range requests as it grows, scrubbed of the sandbox's secrets. `diff.patch`
  is taken as the engine's local backend takes it: against the commit the
  first session found, with no hooks or filters, and nothing at all when the
  checkout's git config defines filter drivers.
- **Credentials.** An API-key session gets `ANTHROPIC_API_KEY` as the exec's
  environment and nothing else. A session on a subscription login gets no
  Anthropic credential, and is refused when the checkout's `.claude`
  settings define `apiKeyHelper` or Anthropic variables. Neither credential
  is ever written by the platform, into instance config, files or argv.
- **Sign-in.** The CLI prints Claude's authorize URL, which the dashboard
  shows; the user signs in on claude.ai and pastes the code. The code
  reaches the container once, as `login-code`'s environment, and goes to the
  CLI through a FIFO. A sign-in that fails or expires removes what the CLI
  wrote. Terminating a sandbox revokes a login in it first.
- **Restart.** `sandbox-app-boot --restart` reruns a ready boot from its
  manifest with the project's secrets passed again, so the edit is live
  before the evaluation that verifies it runs. A restart that loses the app
  fails the sandbox, which can then be resumed like any failed boot.

The image installs Claude Code with Anthropic's own installer, as
`CLAUDE_CODE_VERSION` says (`stable` by default), and records the version
as the image property `claude_code_version`. Sessions run with
`DISABLE_AUTOUPDATER`, so a new version comes only with a new image.

Sign-in on the hosted platform is off until both switches are on:
`CLAUDE_CODE_AUTH=sandbox_login` and `CLAUDE_CODE_HOSTED_LOGIN_ENABLED=true`,
from Terraform. Before switching them on for anyone but the operator, accept
Anthropic's Commercial Terms for hosting Claude Code and confirm the design
with Anthropic, as activeagent#578 says.

## Lifetime

Every sandbox container is labelled `user.expires_at`, copied from its
session's expiry, which is two hours for a checkout.
`IncusSandboxService#cleanup_expired` and the hosts' cron reaper
(`scripts/incus/cleanup-sandboxes.sh`, installed as
`/usr/local/bin/cleanup-sandboxes.sh` and run every five minutes) remove a
container only once that time has passed. A container without the label is
removed 15 minutes after its `user.created_at`. A container with neither
label is left alone.

## Resources and sizing

An app_runtime container uses the `cpu_small` tier unless the session names
another: 2 vCPUs, 8 GB of memory, 500 processes and a 20 GB root disk.
`limits.memory` caps a container's memory; it does not reserve it. The `dir`
storage pool the hosts use does not enforce disk sizes, so the 20 GB is a
declaration only, and every container holds a full copy of the image's root
filesystem.

A local Docker check (arm64) booted a minimal Rails 8 app on PostgreSQL and
bootstrapped the engine into it. These numbers are a floor, not a budget: a
real app's bundle, assets and data are larger.

| | |
| --- | --- |
| Image | 2 GB with one Ruby series preinstalled |
| `/opt/mise` after the boot (one Ruby, Node, Bun, the bundle) | 753 MB |
| Container memory, booted and idle (Puma and PostgreSQL) | about 205 MiB |

On sandbox-staging's n2-standard-4 host (4 vCPUs, 16 GB, 100 GB disk), start
with at most two boots at a time: `bundle install` and asset builds keep a
container's 2 vCPUs busy. Allow no more ready checkouts than the host's memory
and disk hold at the footprint measured there. Measure a real app on the host
before raising either limit.

## Switching checkouts on

Checkouts run a repository's own code, so they stay off in an environment until
its Incus host has the egress controls tracked in
https://github.com/activeagents/activeagents/issues/150.

- **The switch.** `INCUS_APP_RUNTIME_ENABLED` is set from the Terraform
  variable `incus_app_runtime_enabled`. The variable is declared in
  `terraform/variables.tf`, passed through `terraform/main.tf`, and set in each
  `terraform/environments/<env>/main.tf`. Never set it by hand: the next apply
  overwrites it. While the switch is off, `IncusSandboxService#create_sandbox`
  refuses app_runtime sandboxes.
- **The check.** `bin/rails incus:preflight` reports `app_runtime_enabled`,
  `app_runtime_image` (whether the image is present and its
  `boot_spec_version`) and `app_runtime_supported`. The last one is true only
  when the switch is on, the image is present, and its version matches.
- **The dashboard.** `IncusSandboxService.app_runtime_available?` gives the same
  answer from a cached check: five minutes when the answer is yes, one minute
  when it is no. The service reports it to the engine as `features[:app_runtime]`,
  the hook through which the engine's sandbox orchestrator asks a backend to
  describe itself (`SandboxOrchestrator#backend_info`). The Projects entry point
  and its capability checklist live in the engine, and they should read this
  capability before showing Projects. The platform has no Projects links of its
  own yet; any it adds must check the same capability.
