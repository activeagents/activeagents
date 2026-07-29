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

    # The renamed table may predate some columns (staging drift) — add any
    # that are missing before touching their defaults.
    {
      spans: [ :jsonb, { default: [] } ],
      resource_attributes: [ :jsonb, { default: {} } ],
      sdk_info: [ :jsonb, { default: {} } ],
      total_duration_ms: [ :decimal, {} ],
      total_input_tokens: [ :integer, { default: 0 } ],
      total_output_tokens: [ :integer, { default: 0 } ],
      total_thinking_tokens: [ :integer, { default: 0 } ],
      status: [ :string, { default: "UNSET" } ],
      agent_class: [ :string, {} ],
      agent_action: [ :string, {} ],
      error_message: [ :text, {} ],
      service_name: [ :string, {} ],
      environment: [ :string, {} ]
    }.each do |column, (type, options)|
      add_column TABLE, column, type, if_not_exists: true, **options
    end

    # Defaults expected by ActiveAgent::TelemetryTrace.create_from_payload
    change_column_default TABLE, :spans, []
    change_column_default TABLE, :resource_attributes, {}
    change_column_default TABLE, :sdk_info, {}
    change_column_default TABLE, :total_input_tokens, 0
    change_column_default TABLE, :total_output_tokens, 0
    change_column_default TABLE, :total_thinking_tokens, 0
    change_column_default TABLE, :status, "UNSET"

    change_column_null TABLE, :timestamp, false, Time.current if column_exists?(TABLE, :timestamp)

    unless index_exists?(TABLE, [ :account_id, :trace_id ], unique: true)
      add_index TABLE, [ :account_id, :trace_id ], unique: true
    end
    unless index_exists?(TABLE, [ :account_id, :timestamp ])
      add_index TABLE, [ :account_id, :timestamp ]
    end
    unless index_exists?(TABLE, :status)
      add_index TABLE, :status
    end

    # accounts.telemetry_api_key entered schema.rb in April without a
    # migration ever being written, so schema-loaded databases have these
    # while migration-evolved ones (staging) don't. Same defensive guards
    # for the usage-tracking columns the Account model reads at runtime.
    add_column :accounts, :telemetry_api_key, :string, if_not_exists: true
    unless index_exists?(:accounts, :telemetry_api_key, unique: true)
      add_index :accounts, :telemetry_api_key, unique: true
    end
    add_column :accounts, :agent_runs_this_period, :integer, default: 0, null: false, if_not_exists: true
    add_column :accounts, :agent_runs_limit, :integer, default: 3, null: false, if_not_exists: true
    add_column :accounts, :usage_period_start, :datetime, if_not_exists: true

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
