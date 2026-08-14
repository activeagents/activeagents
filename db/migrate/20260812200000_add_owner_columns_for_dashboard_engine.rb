# frozen_string_literal: true

# The dashboard models now come from the activeagent gem's engine, which
# resolves ownership from a column rather than from each app's own
# conventions. Our tables mostly already have the right one; this adds the
# ones they were missing so every dashboard model can answer the same
# question.
#
# Nothing changes about who owns what: agents stay per-user and keys stay
# per-account, because that is the order those models declare. The columns
# that go unused here exist so switching a deployment's ownership shape stays
# a configuration change.
class AddOwnerColumnsForDashboardEngine < ActiveRecord::Migration[8.0]
  def up
    add_column :agents, :account_id, :bigint unless column_exists?(:agents, :account_id)
    add_index :agents, :account_id unless index_exists?(:agents, :account_id)

    add_column :api_keys, :user_id, :bigint unless column_exists?(:api_keys, :user_id)
    add_column :provider_keys, :user_id, :bigint unless column_exists?(:provider_keys, :user_id)

    # Recordings were scoped by an account_id buried in their metadata JSON,
    # which only PostgreSQL could filter on. Promote it to a real column and
    # backfill, so the engine's portable scoping reads the same rows.
    unless column_exists?(:session_recordings, :account_id)
      add_column :session_recordings, :account_id, :bigint
      add_column :session_recordings, :user_id, :bigint
      add_index :session_recordings, :account_id
      add_index :session_recordings, :user_id
    end

    # metadata is a json column, not jsonb, so the ? containment operator
    # is unavailable; ->> already yields NULL for a missing key.
    execute <<~SQL.squish
      UPDATE session_recordings
         SET account_id = NULLIF(metadata->>'account_id', '')::bigint
       WHERE account_id IS NULL
    SQL

    # user_id is the column that decides whether a recording is visible at
    # all. ActionAgent::SessionRecording declares `owned_by :user, :account`
    # and the engine takes the first of those whose class this app configured
    # — both are, so it scopes by user_id and never looks at account_id.
    #
    # Both backfills below are needed because recordings arrive two ways:
    # UserSessionClaimer stamps metadata["user_id"] on a lander recording when
    # the visitor signs up, and those have no sandbox_session to inherit from.
    # Without this one, every recording claimed that way survives the
    # migration with a NULL owner and drops out of the Recordings view.
    execute <<~SQL.squish
      UPDATE session_recordings
         SET user_id = NULLIF(metadata->>'user_id', '')::bigint
       WHERE user_id IS NULL
    SQL

    # Recordings made inside a sandbox belong to whoever opened it.
    execute <<~SQL.squish
      UPDATE session_recordings
         SET user_id = sandbox_sessions.user_id
        FROM sandbox_sessions
       WHERE sandbox_sessions.id = session_recordings.sandbox_session_id
         AND session_recordings.user_id IS NULL
    SQL
  end

  def down
    remove_column :agents, :account_id, if_exists: true
    remove_column :api_keys, :user_id, if_exists: true
    remove_column :provider_keys, :user_id, if_exists: true
    remove_column :session_recordings, :account_id, if_exists: true
    remove_column :session_recordings, :user_id, if_exists: true
  end
end
