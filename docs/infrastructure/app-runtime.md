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
   - the database servers those URLs need, and Redis when the bundle uses it
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
owns them.

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
