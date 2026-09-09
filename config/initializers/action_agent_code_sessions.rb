# frozen_string_literal: true

# Code sessions (actionagent engine): hand an agent, with the findings of its
# evaluations, to a sandboxed coding agent running in a code-on-incus (`coi`)
# container on the platform's Incus host.
#
# This is a no-op until the dashboard engine is in the bundle. On `main` the
# app still ships its own dashboard copy; the engine is mounted by PR #105,
# and this file only adds to what that PR's `ActionAgent.configure` block sets
# up. Guarding on the seam itself (rather than on `defined?(ActionAgent)`
# alone) keeps boot green while the engine and the host land independently.
#
# Runbook: docs/infrastructure/code-agent-sessions.md
if defined?(ActionAgent) && ActionAgent.respond_to?(:code_session_backend)
  # The engine defaults to its in-memory mock; the platform runs the real
  # backend unless a deploy says otherwise (CODE_SESSION_BACKEND=mock is the
  # right answer for a review app without an Incus host).
  ActionAgent.code_session_backend = ENV.fetch("CODE_SESSION_BACKEND", "code_on_incus")

  # The Rails app and the Incus host are different machines here, so every
  # `coi` call travels over SSH. Unset means "coi is on this box", which is
  # what a single-VM staging deploy or a developer laptop wants.
  ActionAgent.code_on_incus.ssh_target = ENV["COI_SSH_TARGET"].presence
  # Per-session state (profile, brief, 0600 secret files, workspace) lives on
  # whichever host runs coi. Leave unset for the engine's tmp/ default.
  ActionAgent.code_on_incus.state_dir = ENV["COI_STATE_DIR"].presence

  # A GitHub token is an account credential like any other provider key
  # (Settings -> Provider API Keys -> GitHub), so it resolves the same way
  # `provider_credentials_resolver` does: through the owner's tenant account.
  # Returning nil means the session gets an anonymous clone and no push; the
  # engine never falls back to ENV["GITHUB_TOKEN"] in multi-tenant mode.
  ActionAgent.github_token_resolver = lambda do |owner, _session|
    ActionAgent.tenant_for(owner)&.provider_key_for("github")&.credential
  end
end
