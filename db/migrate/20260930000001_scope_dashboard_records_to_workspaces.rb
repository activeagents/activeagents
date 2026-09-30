class ScopeDashboardRecordsToWorkspaces < ActiveRecord::Migration[8.1]
  def up
    # Preserve the old primary-account mapping before invitations can add a
    # second workspace. Unowned records remain unowned, never globally visible.
    %w[agents sandbox_sessions session_recordings].each do |table|
      execute <<~SQL
        UPDATE #{table} SET account_id = COALESCE(
          (SELECT MIN(accounts.id) FROM accounts WHERE accounts.owner_id = #{table}.user_id),
          (SELECT MIN(account_memberships.account_id) FROM account_memberships WHERE account_memberships.user_id = #{table}.user_id)
        ) WHERE account_id IS NULL AND user_id IS NOT NULL
      SQL
    end
    remove_index :agents, name: "index_agents_on_slug"
    remove_index :agents, name: "index_agents_on_user_id_and_slug"
    add_index :agents, [ :account_id, :slug ], unique: true
    remove_index :agents, name: "index_agents_on_observed_identity"
    add_index :agents, [ :account_id, :service_name, :agent_class_name, :action_name ],
      unique: true, where: "service_name IS NOT NULL", name: "index_agents_on_observed_identity"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Workspace-scoped slugs may now overlap across accounts."
  end
end
