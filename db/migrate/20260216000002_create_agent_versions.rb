# frozen_string_literal: true

class CreateAgentVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_versions do |t|
      t.references :agent, null: false, foreign_key: true

      t.integer :version_number, null: false, default: 1
      t.string :change_summary

      # Snapshot of agent configuration at this version
      t.jsonb :configuration_snapshot, null: false, default: {}

      # Who made the change
      t.string :created_by

      t.timestamps
    end

    add_index :agent_versions, [:agent_id, :version_number], unique: true
  end
end
