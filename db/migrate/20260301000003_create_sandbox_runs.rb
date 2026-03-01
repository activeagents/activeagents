# frozen_string_literal: true

class CreateSandboxRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :sandbox_runs do |t|
      t.text :task, null: false
      t.integer :status, default: 0, null: false
      t.text :result
      t.text :error
      t.json :screenshots, default: []
      t.integer :tokens_used, default: 0
      t.integer :duration_ms
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :sandbox_runs, :status
    add_index :sandbox_runs, :created_at
  end
end
