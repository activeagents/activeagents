# Sandbox 1.8 deployment readiness

Testing 1.8 through the dashboard requires the 1.8 `activeagent` and
`actionagent` gems, their generated migrations, and the matching assets and
workers deployed together.

## Incus preflight

Run `bin/rails incus:preflight` from the deployed app/worker environment. This is
read-only: it checks certificate trust, the configured project, the restricted
profile and the instance-list API. It does not create a project, grant access,
start a container, or print credentials.

Configure these settings through the deployment's secret mounts and environment:

| Setting | Purpose |
| --- | --- |
| `INCUS_HOST` | Reachable HTTPS daemon endpoint, normally port 8443 |
| `INCUS_PROJECT` | Existing sandbox project, default `agent-sandboxes` |
| `INCUS_CERT_PATH` | Mounted client certificate trusted by that daemon |
| `INCUS_KEY_PATH` | Mounted private key for the client certificate |
| `INCUS_SERVER_CA_PATH` | Optional CA bundle for verifying the daemon certificate |

TLS verification stays enabled. The Rails adapter does not implement Unix socket
transport. Its previous socket branch referenced an unsupported HTTP adapter
setting; it now reports the required HTTPS configuration directly.

The separate `terraform/environments/sandbox-staging` deployment produces
`INCUS_CERT_SECRET` and `INCUS_KEY_SECRET` names. Those are not file paths and the
Rails adapter does not resolve them through Secret Manager. Mount the corresponding
secrets in both the app and worker and set the `*_PATH` variables. The regular
staging deployment does not currently perform that wiring. The app also needs
network routes to the Incus daemon and to the sandbox runtime endpoints.

## Remaining execution support

A successful preflight confirms the daemon connection, not a working 1.8 checkout
sandbox. `IncusSandboxService` boots an `app_runtime` session from the
`sandbox-app-runtime` image: it fetches the repository into the container, runs
the image's boot command, and reads the runtime manifest the app writes for its
MCP endpoint. `app_runtime_supported` in the preflight report says whether the
daemon carries that image. The service does not implement the `run_code_session`
and `cancel_code_session` contract, so `code_sessions_supported` is false and the
orchestrator refuses Claude Code and Codex sessions on this backend.

Before a live Claude Code or Codex test, implement that contract with a suitable
image, per-session ownership, credential isolation, streamed events, cancellation
and diff capture. The framework's local backend provides the tested reference.
The current setup script's base/browser images do not install either coding CLI.

Enter provider credentials only in the deployed dashboard's Integrations form.
Use a small synthetic checkout task first, inspect its transcript and diff, then
run AskActiveAgents and its evaluation scenarios against the checkout runtime.
Verify cancellation and expired-session cleanup before calling the hosted path
ready. The API contract tests use synthetic responses and make no live-model or
live-Incus claim.

References: [Incus REST API](https://linuxcontainers.org/incus/docs/main/rest-api/)
and [recorded exec output](https://linuxcontainers.org/incus/docs/main/api-extensions/#container-exec-recording).
