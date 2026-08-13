# frozen_string_literal: true

# The dashboard's MCP Services view can start a catalog server inside a
# sandbox, and records which ones a session was launched with so a running
# server reads as running instead of offering to start a second copy.
#
# The engine's install generator creates this column with the table; our
# sandbox_sessions predates the engine, so it gets added here. Additive and
# defaulted, so sessions created before this migration read as "no MCP
# servers" rather than nil.
class AddMcpServersToSandboxSessions < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:sandbox_sessions, :mcp_servers)
      add_column :sandbox_sessions, :mcp_servers, :jsonb, default: []
      # Containment (@>) is how the engine looks a server up across sessions.
      add_index :sandbox_sessions, :mcp_servers, using: :gin
    end

    # SandboxSession declares `owned_by :user, :account`, and the engine's
    # own schema carries both columns so a deployment's ownership shape
    # stays a configuration change. Ours had only user_id, which is the one
    # that scopes sandboxes here — add the other so the model can answer the
    # same question every other dashboard model does.
    unless column_exists?(:sandbox_sessions, :account_id)
      add_column :sandbox_sessions, :account_id, :bigint
      add_index :sandbox_sessions, :account_id
    end
  end

  def down
    remove_column :sandbox_sessions, :mcp_servers, if_exists: true
    remove_column :sandbox_sessions, :account_id, if_exists: true
  end
end
