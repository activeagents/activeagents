# frozen_string_literal: true

# The actionagent engine grew since this app's dashboard tables were created:
# evaluations can be scenario suites (user-authored prompts replayed through
# the agent, scored per scenario and per model), and sandbox sessions record
# which MCP servers they were launched with. This brings the platform's
# unprefixed tables up to the engine's current schema
# (create_active_agent_evaluation_scenarios and
# create_active_agent_dashboard_tables in the gem's install generator) so the
# mounted dashboard reads and writes the same columns a self-hosted install
# has. Nothing here changes existing rows.
class AddEngineScenarioAndSandboxColumns < ActiveRecord::Migration[8.0]
  def change
    create_table :evaluation_scenarios do |t|
      t.bigint :evaluation_id, null: false
      t.string :key, null: false
      t.string :group
      t.text :prompt, null: false
      t.text :notes
      t.jsonb :expectations, default: {}
      t.integer :position, default: 0, null: false
      t.boolean :enabled, default: true, null: false
      t.timestamps
      t.index [ :evaluation_id, :key ], unique: true, name: "index_evaluation_scenarios_on_evaluation_and_key"
      t.index [ :evaluation_id, :group ], name: "index_evaluation_scenarios_on_evaluation_and_group"
    end

    create_table :evaluation_scenario_results do |t|
      t.bigint :evaluation_run_id, null: false
      t.bigint :evaluation_scenario_id, null: false
      t.bigint :agent_run_id
      t.string :model, null: false
      t.string :provider
      t.integer :status, default: 0, null: false
      t.float :score
      t.jsonb :scores, default: {}
      t.text :output
      t.jsonb :tool_calls, default: []
      t.integer :duration_ms
      t.integer :input_tokens
      t.integer :output_tokens
      t.decimal :cost, precision: 12, scale: 6
      t.string :fault
      t.text :recommendation
      t.jsonb :diagnosis, default: {}
      t.text :error_message
      t.timestamps
      t.index :evaluation_run_id, name: "index_evaluation_scenario_results_on_run"
      t.index :evaluation_scenario_id, name: "index_evaluation_scenario_results_on_scenario"
      t.index [ :evaluation_run_id, :model ], name: "index_evaluation_scenario_results_on_run_and_model"
    end

    # Which scenarios and models a run covered, so a partial run (one group,
    # one question) reads as such rather than as the whole suite.
    add_column :evaluation_runs, :selection, :jsonb, default: {}

    # MCP servers a sandbox session was started with, so the MCP Services
    # view shows a launched server as running rather than offering to start
    # a second copy.
    add_column :sandbox_sessions, :mcp_servers, :jsonb, default: []
    # The engine declares both owner columns on every owned model; sessions
    # stay owned per user here (see Ownable), so this is never filled in but
    # keeps the association readable.
    add_column :sandbox_sessions, :account_id, :bigint
    add_index :sandbox_sessions, :account_id
  end
end
