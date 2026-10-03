# frozen_string_literal: true

# GitHub connections and checkout sandboxes (activeagents/activeagent#479,
# #482): an account's GitHub OAuth grant and the repositories it made
# available, and the checkout an app_runtime sandbox session boots. Mirrors
# create_active_agent_github_connections in the gem's install generator on
# this app's unprefixed tables.
class AddGithubConnectionsAndCheckoutSandboxes < ActiveRecord::Migration[8.0]
  def change
    create_table :github_connections do |t|
      # Encrypted with Active Record Encryption (ciphertext outgrows a string).
      t.text :access_token, null: false
      t.bigint :github_user_id, null: false
      t.string :login, null: false
      t.string :avatar_url
      t.string :scopes
      t.jsonb :repositories, default: []
      t.bigint :user_id
      t.bigint :account_id
      t.timestamps
      t.index :account_id, unique: true
      t.index :user_id
    end

    change_table :sandbox_sessions do |t|
      t.string :repository
      t.string :repository_ref
      t.string :runtime_mcp_url
      t.text :runtime_mcp_token
    end
  end
end
