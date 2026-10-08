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
  `terraform/variables.tf` and passed through `terraform/main.tf`. Production
  sets it in `terraform/environments/production/main.tf`; staging passes its
  own `incus_app_runtime_enabled` variable, committed in `incus.auto.tfvars`
  (see [Connecting staging to its Incus host](#connecting-staging-to-its-incus-host)).
  Never set it by hand: the next apply overwrites it. While the switch is off,
  `IncusSandboxService#create_sandbox` refuses app_runtime sandboxes.
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

## Connecting staging to its Incus host

Staging's Cloud Run service (`activeagents-staging`, project
`active-agents-platform`) can use the sandbox-staging Incus host
(`terraform/environments/sandbox-staging`) as its sandbox backend. Every
switch below defaults to off, and with all of them off neither environment's
plan changes anything on Cloud Run or on the host.

### What Terraform does once the switches are on

| Switch | Where | What it does |
| --- | --- | --- |
| `platform_network` | sandbox-staging | Peers `sandbox-network` with the staging VPC, exporting its custom routes. Passes `platform_egress_ranges` to the host module, which then routes `10.100.0.0/24` (incusbr0) to the host, sets `can_ip_forward` on it, and admits only that range: on 8443 to the Incus API and on 8080 to the bridge |
| `enable_incus_backend` | staging | Sets `SANDBOX_BACKEND=incus`, `INCUS_HOST` (from `incus_api_url`), `INCUS_PROJECT=agent-sandboxes`, `INCUS_CERT_PATH`, `INCUS_KEY_PATH` and `INCUS_SERVER_CA_PATH`. Mounts `incus-client-cert-staging`, `incus-client-key-staging` and `incus-server-cert-staging` (from `incus_secret_project`) as files in the service and the migrate job. With `incus_host_network` set, peers the staging VPC with the host's and denies connections opened from `incus_host_ranges` into it |
| `incus_app_runtime_enabled` | staging | `INCUS_APP_RUNTIME_ENABLED=true` |
| `claude_code_auth` | staging | `CLAUDE_CODE_AUTH`, passed only when it is `sandbox_login` |
| `claude_code_hosted_login_enabled` | staging | `CLAUDE_CODE_HOSTED_LOGIN_ENABLED=true`, passed only when true |

Cloud Run already sends private ranges through the staging VPC connector
(`PRIVATE_RANGES_ONLY`), so the Incus API and the containers' addresses on the
bridge leave through it with a source address in `10.8.0.0/28`. The host's
firewall admits that range and nothing else on those ports.

### Decide before you start

1. **How Cloud Run reaches the host.** The host runs in sandbox-staging's
   project (default `activeagents-staging`) on `sandbox-network`, and Cloud
   Run runs in `active-agents-platform` on the `activeagents-staging` VPC. A
   Serverless VPC Access connector serves only its own project, so Cloud Run
   cannot use sandbox-staging's `sandbox-connector`. The Terraform here peers
   the two VPCs, one side from each environment, and exports the host's
   bridge route over the peering. It is the only path implemented. The
   alternatives, a Shared VPC or rebuilding the host inside the platform's
   project and VPC, would each need a change to these modules. Before choosing
   peering, check:
   - No range overlaps across the two VPCs. The staging VPC holds
     `10.0.0.0/24`, `10.8.0.0/28` and Cloud SQL's private services range,
     which Google chose: read it with
     `gcloud compute addresses describe activeagents-staging-sql-ip --global --project=active-agents-platform`.
     sandbox-staging holds `10.10.0.0/24`, `10.10.1.0/28`, `10.10.2.0/28`, and
     the bridge `10.100.0.0/24`.
   - The peering is a path for traffic opened from the host into the staging
     VPC. `activeagents-staging-deny-from-incus-host` denies it ahead of
     `allow_internal`, and Cloud SQL is not reachable through a second peering.
   - Setting `platform_network` turns on `can_ip_forward` on the running
     host. The Google provider (5.x) changes it in place with
     `instances.update`; GCE may restart the VM to apply it, so do it while no
     sandbox is in use. If a plan ever shows `incus-host-staging` replaced
     instead, stop: a new VM regenerates the client certificate and key
     (publishing new secret versions), has no app-runtime image or
     containers, and may get another internal IP, so steps 3 to 7 would have
     to be repeated.
2. **Which project holds the host's secrets.** The host publishes its client
   certificate, key and server certificate in its own project. Set
   `incus_secret_project` to that project, preferably as its number
   (`gcloud projects describe <project_id> --format='value(projectNumber)'`):
   Cloud Run may report a secret from another project by number, and an ID
   would then show as a change on every plan. The host module already lets
   `activeagents-staging@active-agents-platform.iam.gserviceaccount.com` read
   all three.

The app trusts the daemon only through `INCUS_SERVER_CA_PATH`: it verifies
the daemon's certificate against that file and checks that the certificate
names the address in `INCUS_HOST`. It has no trust-on-first-use. Step 4 covers
both.

### Steps

1. **Apply sandbox-staging, with the egress ACL.** Follow
   [Incus host: sandbox egress and IAM](gcp-cicd-setup.md#incus-host-sandbox-egress-and-iam)
   (the controls tracked in
   https://github.com/activeagents/activeagents/issues/150), applying with the
   platform switches set:

   ```bash
   cd terraform/environments/sandbox-staging
   terraform plan \
     -var platform_network=projects/active-agents-platform/global/networks/activeagents-staging \
     -var 'platform_egress_ranges=["10.8.0.0/28"]'
   terraform apply # with the same -var flags
   ```

   The plan should update `incus-host-staging` in place (`can_ip_forward`),
   narrow `incus-api-staging` to `10.8.0.0/28`, and add the route
   `incus-bridge-staging`, the rule `incus-bridge-app-staging`, the peering,
   and the secret `incus-server-cert-staging` with its two bindings. The staging environment's `vpc_self_link` and `vpc_connector_cidr`
   outputs give both values. sandbox-staging has no committed tfvars and no
   workflow applies it, so pass the same flags on every later apply, or the
   next one removes the route, the rules and the peering again.

   A host built from the module applies the ACL in its startup script; a host
   that predates the ACL gets it from step 4 of that section.

2. **Confirm the ACL acceptance checks.** Run
   [Check from a container](gcp-cicd-setup.md#check-from-a-container) on the
   host. Every probe prints `rejected`; `apt-get`, `git ls-remote` and
   `gem fetch` succeed, and the final `curl` gets `200`. The peering adds two
   more checks, from a VM in the staging VPC or once Cloud Run is connected:
   the container's port 8080 answers from `10.8.0.0/28`, and nothing on the
   bridge can open a connection into the staging VPC. The ACL rejects
   container traffic to `10.0.0.0/8`; replies to a connection Cloud Run opens
   pass only if Incus tracks the connection, so a checkout that never turns
   ready from Cloud Run while the `curl` from the host works points here.

3. **Build the app-runtime image** on the host, as root, from a checkout of
   this repository:

   ```bash
   sudo scripts/build-app-runtime-image.sh
   ```

   A new host VM has no image, so run this again whenever the host is
   recreated.

4. **Make the daemon's certificate name its address, and publish it.** A host
   built from the module after this change does both in its startup script.
   A host that already exists never reruns that script, so on it, as root:

   ```bash
   openssl x509 -in /var/lib/incus/server.crt -noout -ext subjectAltName
   ```

   The list must include the internal IP in `incus_api_url`. A certificate
   Incus generated never does: it names only the host name, `127.0.0.1` and
   `::1` (verified in Incus's source, `GenerateMemCert` in
   `shared/tls/cert.go`). Incus also generates one only when `server.crt` or
   `server.key` is missing (verified in the source and in its authentication
   docs), so changing `core.https_address` and restarting does not help, and
   neither does deleting the pair to regenerate it. Instead, install a
   certificate that names the IP. Incus serves whatever pair it finds
   (verified in the source). `scripts/setup-incus-host.sh server-cert <ip>`
   writes a self-signed pair naming the IP, keeps the old one as
   `*.generated`, and restarts the daemon. It was tested against the app's TLS
   client but not yet on a live host, and the restart is best done while no
   sandbox is in use. From the repository root, run the command printed by
   `terraform -chdir=terraform/environments/sandbox-staging output -raw server_cert_command`.
   It streams the script to the host over `gcloud compute ssh`, as
   `egress_acl_command` does, and publishes the result. Add
   `--tunnel-through-iap` if the host takes no direct SSH.

   On a host whose certificate already names the IP, publish it alone:

   ```bash
   sudo gcloud secrets versions add incus-server-cert-staging --project <host project> --data-file=/var/lib/incus/server.crt
   ```

   Publish again whenever the certificate changes.

5. **Confirm the three secrets have versions.** Cloud Run refuses a revision
   whose secret has none:

   ```bash
   gcloud secrets versions list incus-client-cert-staging --project=<host project>
   gcloud secrets versions list incus-client-key-staging --project=<host project>
   gcloud secrets versions list incus-server-cert-staging --project=<host project>
   ```

   If a client secret lists nothing, publish it from the host as in step 3 of
   [Apply](gcp-cicd-setup.md#apply); for the server certificate, step 4.

6. **Set the staging variables.** Print the host's values with
   `terraform -chdir=terraform/environments/sandbox-staging output -raw environment_config`,
   and commit them with the switches in
   `terraform/environments/staging/incus.auto.tfvars`:

   ```hcl
   # The sandbox-staging Incus host. See docs/infrastructure/app-runtime.md
   # (Connecting staging to its Incus host) before changing a value.
   enable_incus_backend = true
   incus_api_url        = "https://10.10.0.x:8443"            # sandbox-staging's incus_api_url output
   incus_secret_project = "123456789012"                      # the host's project, by number
   incus_host_network   = "https://www.googleapis.com/compute/v1/projects/activeagents-staging/global/networks/sandbox-network"
   incus_host_ranges    = ["10.10.0.0/24", "10.10.1.0/28", "10.10.2.0/28", "10.100.0.0/24"]

   incus_app_runtime_enabled = true

   # Claude Code sign-in in sandboxes. Read step 9 first.
   claude_code_auth                 = "sandbox_login"
   claude_code_hosted_login_enabled = true
   ```

   `enable_incus_backend` without `incus_api_url` fails the plan.

7. **Merge to `main`.** `deploy-staging.yml` applies the file. Its plan should
   add the peering and the firewall rule, and change the service and the
   migrate job only by the new variables and the three secret mounts.

8. **Run the preflight** in the migrate job, which has the service's variables,
   mounts and VPC egress:

   ```bash
   gcloud run jobs execute activeagents-staging-migrate --project=active-agents-platform \
     --region=us-central1 --args=incus:preflight --wait
   gcloud logging read 'resource.type="cloud_run_job" AND resource.labels.job_name="activeagents-staging-migrate"' \
     --project=active-agents-platform --freshness=10m --order=asc --format='value(textPayload)'
   ```

   Expect `"connected": true`, `"project": "agent-sandboxes"`,
   `"app_runtime_enabled": true`, `"app_runtime_image": { "present": true }`
   with `boot_spec_version` equal to `expected_boot_spec_version`, and
   `"app_runtime_supported": true`. What a failure means:

   | Message | Look at |
   | --- | --- |
   | `execution expired`, `Failed to open TCP connection` | the peering is not ACTIVE on both sides, the route, or the 8443 firewall rule |
   | `certificate verify failed` | the latest `incus-server-cert-staging` is not the certificate the daemon serves: publish it again (step 4), then redeploy so new instances read it |
   | `hostname "<ip>" does not match the server certificate` | the certificate does not name the IP in `incus_api_url`: run step 4's `server_cert_command`, or update `incus_api_url` if the host's IP changed |
   | `Incus did not authenticate this client certificate` | the secrets' latest versions are not the certificate the host trusts (`incus config trust list`) |
   | `app_runtime_image.present` is false, or the versions differ | step 3 |

   The preflight checks the API only. The bridge is proven by the first
   checkout turning ready, because the service polls
   `http://<container_ip>:8080` from Cloud Run.

9. **Gate Claude Code sign-in.** Before anyone but the operator signs in to
   Claude Code in a staging sandbox, record both items of
   [activeagents/activeagent#578 §9](https://github.com/activeagents/activeagent/issues/578):
   - Anthropic's Commercial Terms for hosting Claude Code are accepted.
   - Anthropic has confirmed the design, in particular relaying the pasted
     sign-in code into the CLI's stdin and the one-click, one-session rule for
     the fix loop.

   Until both are recorded, the switches in step 6 may be on only while the
   operator is the only person who can open a checkout on staging. Otherwise
   commit `claude_code_auth = "api_key"` and
   `claude_code_hosted_login_enabled = false` in step 6, and turn them on once
   the gate is passed.

To turn everything off, set `enable_incus_backend` and the other switches back
to their defaults in `incus.auto.tfvars` and merge; then apply sandbox-staging
without `platform_network`, which removes the route, the bridge rule and the
peering, widens `incus-api-staging` back to `10.0.0.0/8`, and turns
`can_ip_forward` off again.
