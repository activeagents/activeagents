# frozen_string_literal: true

class CreateSandboxSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :sandbox_sessions do |t|
      t.string :session_id, null: false
      t.references :user, foreign_key: true # null for anonymous free users
      t.references :agent_template, foreign_key: true

      # Session metadata
      t.string :sandbox_type, default: "playwright_mcp"
      t.integer :status, default: 0 # pending, provisioning, ready, running, completed, expired, failed
      t.string :cloud_run_job_id
      t.string :cloud_run_url

      # Execution tracking
      t.integer :runs_count, default: 0
      t.integer :max_runs, default: 10
      t.integer :timeout_seconds, default: 300
      t.datetime :expires_at
      t.datetime :last_activity_at

      # Resource usage
      t.integer :total_tokens, default: 0
      t.integer :total_duration_ms, default: 0

      # Results
      t.jsonb :runs, default: []
      t.text :error_message

      t.timestamps
    end

    add_index :sandbox_sessions, :session_id, unique: true
    add_index :sandbox_sessions, :status
    add_index :sandbox_sessions, :sandbox_type
    add_index :sandbox_sessions, :expires_at
    add_index :sandbox_sessions, :cloud_run_job_id
  end
end
