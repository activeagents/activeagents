# frozen_string_literal: true

# The hosted counterpart of the actionagent engine's add_agent_releases
# migration (activeagent 1.6.2). An agent version cut on deploy carries the
# digest of what the model was given and the deploy's revision, and every
# trace, run and evaluation run records the version it ran under. The engine's
# template names its prefixed tables; this app mounts the engine with an empty
# table_name_prefix, so the same columns go on the unprefixed tables here.
class AddAgentReleases < ActiveRecord::Migration[8.0]
  def change
    add_column :agents, :release_digest, :string

    add_column :agent_versions, :release_digest, :string
    add_column :agent_versions, :revision, :string
    add_index :agent_versions, [ :agent_id, :release_digest ]

    %i[active_agent_telemetry_traces agent_runs evaluation_runs].each do |table|
      add_column table, :agent_version_id, :bigint
      add_index table, :agent_version_id
    end
  end
end
