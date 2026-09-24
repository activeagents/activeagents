# frozen_string_literal: true

# An evaluation run an application executed itself and published to
# POST /v1/evaluations (ExternalEvaluationImport) is identified by the run_id
# the application minted, within the account whose key published it. The
# digest is of the published report, so an identical retry resolves to the
# same run and different content under the same run_id is refused.
class AddExternalReportIdentityToEvaluationRuns < ActiveRecord::Migration[8.2]
  def change
    add_reference :evaluation_runs, :account, foreign_key: { on_delete: :nullify }, index: false
    add_column :evaluation_runs, :external_run_id, :string
    add_column :evaluation_runs, :external_report_digest, :string
    add_index :evaluation_runs, [ :account_id, :external_run_id ], unique: true, where: "external_run_id IS NOT NULL"
  end
end
