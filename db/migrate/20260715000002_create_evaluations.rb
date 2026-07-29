# frozen_string_literal: true

# Evaluations score an agent's persisted generations (solid_agent's
# agent_generations) against rule-based criteria and, when a provider is
# configured, an LLM judge. Idempotent by table (skips environments where
# the tables already exist).
class CreateEvaluations < ActiveRecord::Migration[8.2]
  def up
    unless table_exists?(:evaluations)
      create_table :evaluations do |t|
        t.references :agent, null: false, foreign_key: true
        t.string :name, null: false
        t.string :judge_kind, null: false, default: "rules" # rules | llm
        t.string :judge_model
        t.jsonb :criteria, null: false, default: []
        t.integer :sample_size, null: false, default: 20

        t.timestamps
      end

      add_index :evaluations, [ :agent_id, :name ], unique: true
    end

    unless table_exists?(:evaluation_runs)
      create_table :evaluation_runs do |t|
        t.references :evaluation, null: false, foreign_key: true
        t.integer :status, null: false, default: 0 # pending/running/complete/failed
        # { criterion_key => { "score" =>, "min" =>, "max" =>, "passed" =>, "total" => } }
        t.jsonb :scores, default: {}
        t.integer :samples_evaluated, default: 0
        t.integer :samples_passed, default: 0
        t.text :error_message
        t.datetime :completed_at

        t.timestamps
      end

      add_index :evaluation_runs, [ :evaluation_id, :created_at ]
      add_index :evaluation_runs, :status
    end
  end

  def down
    drop_table :evaluation_runs, if_exists: true
    drop_table :evaluations, if_exists: true
  end
end
