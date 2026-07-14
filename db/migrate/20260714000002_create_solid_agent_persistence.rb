# frozen_string_literal: true

# Persistence layer for agent conversations, from the solid_agent gem's
# install generator (agent_contexts / agent_messages / agent_generations),
# with platform additions for observability correlation:
#
# - agent_generations.trace_id + provenance: joins each generation to its
#   telemetry trace (active_agent_telemetry_traces.trace_id) and records
#   the SolidAgent provenance hash (prompt/context/agent checksums)
# - agent_messages.provenance + content_checksum: populated automatically
#   by SolidAgent::HasContext when the columns exist (duck-typed)
class CreateSolidAgentPersistence < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_contexts do |t|
      t.references :contextable, polymorphic: true, index: true
      t.string :agent_name, null: false
      t.string :action_name, null: false
      t.text :instructions
      t.jsonb :options, default: {}
      t.string :trace_id, index: true
      t.integer :total_input_tokens, default: 0
      t.integer :total_output_tokens, default: 0

      t.timestamps
    end

    add_index :agent_contexts, [ :agent_name, :action_name ]
    add_index :agent_contexts, :created_at

    create_table :agent_messages do |t|
      t.references :agent_context, null: false, foreign_key: true, index: true
      t.string :role, null: false
      t.text :content
      t.string :tool_call_id
      t.string :tool_name
      t.jsonb :tool_arguments, default: {}
      t.jsonb :tool_result
      t.jsonb :attachments, default: []
      t.jsonb :metadata, default: {}

      # Platform additions (SolidAgent::HasContext populates these when present)
      t.jsonb :provenance, default: {}
      t.string :content_checksum

      t.timestamps
    end

    add_index :agent_messages, :role
    add_index :agent_messages, :tool_call_id
    add_index :agent_messages, [ :agent_context_id, :created_at ]

    create_table :agent_generations do |t|
      t.references :agent_context, null: false, foreign_key: true, index: true
      t.text :content
      t.string :model
      t.string :provider
      t.string :finish_reason
      t.integer :input_tokens, default: 0
      t.integer :output_tokens, default: 0
      t.jsonb :tool_calls, default: []
      t.jsonb :raw_response
      t.float :duration_seconds

      # Platform additions: telemetry correlation + provenance
      t.string :trace_id, index: true
      t.jsonb :provenance, default: {}

      t.timestamps
    end

    add_index :agent_generations, :model
    add_index :agent_generations, :finish_reason
    add_index :agent_generations, [ :agent_context_id, :created_at ]
  end
end
