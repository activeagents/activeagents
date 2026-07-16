# frozen_string_literal: true

# Aligns the platform's trace storage with the activeagent gem's telemetry
# schema so the hosted TelemetryTrace model can inherit the gem's
# ActiveAgent::TelemetryTrace implementation directly.
#
# The previously-created telemetry_traces table was orphaned (no model, no
# ingest path ever shipped); it is renamed to the gem's canonical
# active_agent_telemetry_traces name — the same table a self-hosted install
# gets from the gem's dashboard install generator (--multi_tenant).
#
# Also backfills telemetry API keys for existing accounts.
class AlignTelemetryTracesWithActiveAgent < ActiveRecord::Migration[8.2]
  TABLE = :active_agent_telemetry_traces

  def up
    if table_exists?(:telemetry_traces) && !table_exists?(TABLE)
      rename_table :telemetry_traces, TABLE
    end

    unless table_exists?(TABLE)
      create_table TABLE do |t|
        t.references :account, foreign_key: true, null: false

        t.string :trace_id, null: false
        t.string :service_name
        t.string :environment

        t.datetime :timestamp, null: false

        t.jsonb :spans, default: []
        t.jsonb :resource_attributes, default: {}
        t.jsonb :sdk_info, default: {}

        t.decimal :total_duration_ms
        t.integer :total_input_tokens, default: 0
        t.integer :total_output_tokens, default: 0
        t.integer :total_thinking_tokens, default: 0

        t.string :status, default: "UNSET"

        t.string :agent_class
        t.string :agent_action

        t.text :error_message

        t.timestamps
      end

      add_index TABLE, :trace_id
      add_index TABLE, :timestamp
      add_index TABLE, :service_name
      add_index TABLE, :agent_class
    end

    # Defaults expected by ActiveAgent::TelemetryTrace.create_from_payload
    change_column_default TABLE, :spans, []
    change_column_default TABLE, :resource_attributes, {}
    change_column_default TABLE, :sdk_info, {}
    change_column_default TABLE, :total_input_tokens, 0
    change_column_default TABLE, :total_output_tokens, 0
    change_column_default TABLE, :total_thinking_tokens, 0
    change_column_default TABLE, :status, "UNSET"

    change_column_null TABLE, :timestamp, false, Time.current

    unless index_exists?(TABLE, [ :account_id, :trace_id ], unique: true)
      add_index TABLE, [ :account_id, :trace_id ], unique: true
    end
    unless index_exists?(TABLE, [ :account_id, :timestamp ])
      add_index TABLE, [ :account_id, :timestamp ]
    end
    unless index_exists?(TABLE, :status)
      add_index TABLE, :status
    end

    # Backfill telemetry API keys for accounts created before the key
    # generation callback existed.
    Account.reset_column_information
    Account.where(telemetry_api_key: nil).find_each do |account|
      account.update_columns(telemetry_api_key: SecureRandom.base58(36))
    end
  end

  def down
    rename_table TABLE, :telemetry_traces if table_exists?(TABLE)
  end
end
