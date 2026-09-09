# frozen_string_literal: true

class AddExternalEvaluationReports < ActiveRecord::Migration[8.2]
  def change
    add_reference :evaluations, :account, foreign_key: true
    add_column :evaluations, :external_key, :string
    add_index :evaluations, [ :account_id, :external_key ], unique: true
    add_reference :evaluation_runs, :account, foreign_key: true
    add_column :evaluation_runs, :external_run_id, :string
    add_column :evaluation_runs, :report_digest, :string
    add_column :evaluation_runs, :external_report, :jsonb
    add_index :evaluation_runs, [ :account_id, :external_run_id ], unique: true
  end
end
