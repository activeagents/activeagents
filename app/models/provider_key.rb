# frozen_string_literal: true

# Per-account LLM provider credential (Settings -> Provider API Keys).
# Generation runs (AgentExecutionService and the evaluation LLM judge)
# prefer these over the platform's ENV-configured keys, so users can run
# agents with their own OpenAI/Anthropic/OpenRouter accounts — or point
# ollama at their own host (e.g. a tunnel to a locally running instance).
#
# "github" is the one non-LLM entry: a personal access token that code
# sessions (the actionagent engine's sandboxed coding agents) use to clone
# and, with write access, push to the account's repositories. It is stored
# and masked exactly like an API key, and read through
# ActionAgent.github_token_resolver (config/initializers/action_agent_code_sessions.rb),
# never through generation_options.
#
# The credential is encrypted at rest with Active Record Encryption. API
# keys are never rendered back to the client — only a masked hint; ollama
# hosts are not secret and are shown in full (see #display_hint).
class ProviderKey < ApplicationRecord
  # Providers that authenticate with an API key (or, for GitHub, a token).
  KEY_PROVIDERS = %w[openai anthropic openrouter github].freeze
  # Providers addressed by host URL instead of a key.
  HOST_PROVIDERS = %w[ollama].freeze
  PROVIDERS = (KEY_PROVIDERS + HOST_PROVIDERS).freeze

  belongs_to :account

  encrypts :credential

  validates :provider, presence: true, inclusion: { in: PROVIDERS },
    uniqueness: { scope: :account_id }
  validates :credential, presence: true, length: { maximum: 500 }
  validates :credential, format: { with: %r{\Ahttps?://\S+\z}, message: "must be an http(s):// URL" },
    if: :host_based?

  def host_based?
    HOST_PROVIDERS.include?(provider)
  end

  # Options merged into generate_with for runs on this account, overriding
  # the platform's config/active_agent.yml credentials.
  def generation_options
    host_based? ? { host: credential } : { access_token: credential }
  end

  # "sk-a…Q2z9" for keys; hosts are shown in full.
  def display_hint
    return credential if host_based?

    "#{credential.first(4)}…#{credential.last(4)}"
  end
end
