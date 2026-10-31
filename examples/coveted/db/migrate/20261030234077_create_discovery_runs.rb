class CreateDiscoveryRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :discovery_runs do |t|
      t.references :hunt, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.string :trigger, null: false, default: "manual"
      t.datetime :started_at
      t.datetime :finished_at
      t.text :summary
      t.string :confidence
      t.json :queries
      t.integer :candidate_count, null: false, default: 0
      t.integer :new_findings_count, null: false, default: 0
      t.string :scored_by
      t.string :provider
      t.string :model
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.string :trace_id
      t.integer :fee_cents, null: false, default: 0
      t.text :error_message

      t.timestamps
    end

    add_index :discovery_runs, :trace_id
    add_index :discovery_runs, [ :hunt_id, :status ]
  end
end
