# frozen_string_literal: true

# The hosted counterpart of the actionagent engine's
# add_evaluation_report_identity migration. An evaluation run an application
# executed itself and published (ActionAgent::EvaluationReportImport) is
# identified by the account whose key published it and the run_id the
# application minted, and carries the digest of the report, so an identical
# retry resolves to the same run and different content under the same run_id
# is refused. All three columns are NULL for a run the dashboard executed.
#
# The engine's template names its prefixed table; this app mounts the engine
# with an empty table_name_prefix, so the columns go on evaluation_runs here.
class AddEvaluationReportIdentity < ActiveRecord::Migration[8.2]
  def change
    add_column :evaluation_runs, :external_tenant, :string
    add_column :evaluation_runs, :external_run_id, :string
    add_column :evaluation_runs, :external_report_digest, :string
    add_index :evaluation_runs, [ :external_tenant, :external_run_id ], unique: true,
      name: "index_evaluation_runs_on_external_identity"
  end
end
