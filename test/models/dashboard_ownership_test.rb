# frozen_string_literal: true

require "test_helper"

# The engine's models name the user first; this platform re-declares them from
# `to_prepare` so the account is the authorization boundary. A model left off
# that list is owned per user, and the engine refuses an Account as its owner.
class DashboardOwnershipTest < ActiveSupport::TestCase
  ACCOUNT_OWNED = [
    ActionAgent::Agent, ActionAgent::SandboxSession, ActionAgent::SessionRecording, ActionAgent::CodeSession,
    ActionAgent::ProviderKey, ActionAgent::ApiKey, ActionAgent::GithubConnection
  ].freeze

  test "every owned dashboard model is owned by the account" do
    ACCOUNT_OWNED.each do |model|
      assert_equal :account, model.owner_association, "#{model.name} must be owned by the account"
    end
  end
end
