class CreateTelemetryTraces < ActiveRecord::Migration[8.2]
  def change
    create_table :telemetry_traces do |t|
      t.references :account, null: false, foreign_key: true
      t.string :trace_id
      t.string :service_name
      t.string :environment
      t.datetime :timestamp
      t.jsonb :spans
      t.jsonb :resource_attributes
      t.jsonb :sdk_info
      t.decimal :total_duration_ms
      t.integer :total_input_tokens
      t.integer :total_output_tokens
      t.integer :total_thinking_tokens
      t.string :status
      t.string :agent_class
      t.string :agent_action
      t.text :error_message

      t.timestamps
    end
    add_index :telemetry_traces, :trace_id
    add_index :telemetry_traces, :service_name
    add_index :telemetry_traces, :timestamp
    add_index :telemetry_traces, :agent_class
  end
end
