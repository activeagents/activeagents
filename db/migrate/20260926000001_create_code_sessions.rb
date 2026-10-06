# frozen_string_literal: true

# Claude Code sessions run inside an app_runtime sandbox's checkout
# (activeagents/activeagent#491). Mirrors create_active_agent_code_sessions in
# the gem's install generator on this app's unprefixed tables.
class CreateCodeSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :code_sessions do |t|
      t.bigint :sandbox_session_id, null: false
      t.text :prompt, null: false
      t.integer :status, default: 0, null: false
      t.jsonb :events, default: []
      t.integer :dropped_events_count, default: 0, null: false
      t.text :result
      t.text :diff
      t.text :error_message
      t.string :model
      t.string :claude_session_id
      t.integer :num_turns
      t.integer :duration_ms
      t.decimal :total_cost_usd, precision: 12, scale: 6
      t.integer :input_tokens
      t.integer :output_tokens
      t.datetime :started_at
      t.datetime :finished_at
      t.bigint :user_id
      t.bigint :account_id
      t.timestamps
      t.index :sandbox_session_id
      t.index :user_id
      t.index :account_id
    end
  end
end
