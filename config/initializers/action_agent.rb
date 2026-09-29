# frozen_string_literal: true

# The hosted platform is the multi-tenant deployment of the actionagent gem's
# dashboard engine. The engine owns the product surface — agents, runs,
# conversations, evaluations, traces, metrics, sandboxes, recordings — and
# this app supplies the things a hosted product has and a self-hosted install
# does not: accounts, sessions, plans and billing, and cloud sandbox
# infrastructure.
#
# Everything below is a seam the engine exposes for exactly that purpose. A
# self-hosted install leaves all of it unset and gets the same dashboard,
# single-user and unmetered.
ActionAgent.configure do |config|
  # --- Tenancy ------------------------------------------------------------
  # Traces belong to accounts; ingest authenticates a per-account key.
  config.multi_tenant = true
  config.account_class = "Account"
  config.user_class = "User"
  # The engine's controllers are their own base class, so our Authentication
  # concern isn't on them — session lookup and actor resolution are supplied
  # here instead of named as methods to call.
  config.authentication_method = lambda do |controller|
    Current.session ||= Session.find_by(id: controller.send(:cookies).signed[:session_id])
    Current.user&.email_verified? && Current.account.present?
  end

  config.current_user_resolver = ->(_controller) { Current.session&.user }
  # A browser that reaches the dashboard signed out is sent to this app's
  # sign-in page (API and MCP clients still get a bare 401), and the
  # dashboard header's sign-out posts to this app's session.
  config.sign_in_path = "/session/new"
  config.sign_out_path = "/session"
  config.current_account_resolver = ->(_controller) { Current.account }

  # Every dashboard record is workspace-scoped, even when one user owns
  # multiple workspaces. Never infer a workspace from an agent's creator.
  config.agent_scope_resolver = lambda do |owner|
    case owner
    when Account then Agent.where(account_id: owner.id)
    else Agent.none
    end
  end

  # Traces belong to accounts, so an agent's user owner maps to their account.
  config.tenant_resolver = ->(owner) { owner.is_a?(User) ? owner.primary_account : owner }

  # Our TelemetryTrace subclass adds the mandatory account association and
  # token-total dedup on top of the gem's.
  config.trace_model_class = "TelemetryTrace"

  # --- Schema -------------------------------------------------------------
  # These tables predate the engine and are not prefixed. Renaming production
  # tables to match a convention would be all risk and no benefit.
  config.table_name_prefix = ""

  # Polymorphic rows (agent_memories, agent_contexts) were written under this
  # app's own Agent constant, which is now an alias of the engine's class.
  config.agent_polymorphic_name = "Agent"

  # --- Plans and billing --------------------------------------------------
  # Run limits come from the account's plan. Returning a message denies the
  # action; nil allows it.
  # Owners reaching the dashboard can be users or accounts, but plans hang
  # off accounts, so both resolve through tenant_for below.
  #
  # A published evaluation report (/v1/evaluations) is refused once the
  # account is over its plan's trace quota, with the body /v1/traces answers
  # its 429 with. The engine asks only before storing a new report, so an
  # identical retry still gets its receipt.
  config.quota_checker = lambda do |owner, kind|
    account = ActionAgent.tenant_for(owner)
    next nil if account.nil?

    case kind
    when :execution
      next nil if account.can_run_agent?

      {
        message: "You've used all #{account.effective_agent_runs_limit} agent runs this month. Upgrade to continue.",
        usage: account.usage_stats
      }
    when :evaluation_report
      next nil if account.can_ingest_traces?

      { error: "Trace quota exceeded for current plan", limit: account.effective_trace_limit }
    end
  end

  config.usage_recorder = lambda do |owner, kind|
    account = ActionAgent.tenant_for(owner)
    account.increment_agent_runs! if kind == :execution && account.respond_to?(:increment_agent_runs!)
  end

  config.upgrade_url = "/pricing"

  # Retention follows the plan (free 3 days, pro 14, enterprise 400) — the
  # promise the pricing page makes.
  config.trace_retention = ->(account) { account&.trace_retention || Account::TRACE_RETENTION.fetch("free") }

  # --- Credentials --------------------------------------------------------
  # An account's own provider key beats the platform's ENV credentials, so
  # people can run agents on their own OpenAI/Anthropic accounts, or point
  # ollama at a host of their own.
  config.provider_credentials_resolver = lambda do |owner, provider|
    ActionAgent.tenant_for(owner)&.provider_key_for(provider)&.generation_options
  end

  # --- Attribution --------------------------------------------------------
  # Observed agents belong to the publishing workspace. The host concern
  # retains its owning user as attribution, not as the tenant boundary.
  config.trace_owner_resolver = ->(trace) { trace.account }

  # --- Sandboxes ----------------------------------------------------------
  # The engine ships the in-memory backend; the infrastructure this platform
  # operates is registered here.
  config.sandbox_backends = {
    "incus" => "IncusSandboxService",
    "kubernetes" => "KubernetesSandboxService",
    "cloud_run" => "CloudRunService"
  }
  config.sandbox_service = ENV.fetch("SANDBOX_BACKEND", "incus")
end

Rails.application.config.to_prepare do
  # The engine supports both owners. This hosted app uses accounts; keeping
  # user as optional attribution must not make it the authorization boundary.
  [ ActionAgent::Agent, ActionAgent::SandboxSession, ActionAgent::SessionRecording ].each do |model|
    model.owned_by :account, :user
  end
  ActionAgent::Agent.include WorkspaceAgentAttribution
end
