# frozen_string_literal: true

# The dashboard (the actionagent gem) for this demo: mounted at /activeagents
# in development only, so there is nothing to authenticate — see
# config/routes.rb. A real install sets an authentication_method: traces carry
# prompts, outputs and error messages.
#
# Everything else the engine offers (multi-tenancy, ingest keys, sandbox
# backends, quota hooks) is documented in the gem's README and in
# docs/framework/self-hosted-observability.md.
ActionAgent.configure do |config|
  config.authentication_method = nil
end
