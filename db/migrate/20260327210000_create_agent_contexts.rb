# frozen_string_literal: true

class CreateAgentContexts < ActiveRecord::Migration[8.2]
  def change
    # Prompts - versioned prompt templates
    create_table :agent_prompts do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :name, null: false
      t.text :content, null: false
      t.string :content_hash
      t.integer :version, default: 1
      t.jsonb :variables, default: []
      t.timestamps
    end
    add_index :agent_prompts, [ :agent_id, :name, :version ], unique: true

    # Instructions - reusable instruction sets
    create_table :agent_instructions do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :name, null: false
      t.text :content, null: false
      t.integer :priority, default: 0
      t.string :scope, default: "system"
      t.timestamps
    end
    add_index :agent_instructions, [ :agent_id, :name ], unique: true

    # Toolsets - tool collections
    create_table :agent_toolsets do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :name, null: false
      t.jsonb :tools, default: []
      t.boolean :enabled, default: true
      t.timestamps
    end
    add_index :agent_toolsets, [ :agent_id, :name ], unique: true

    # Contexts - conversation/session state
    create_table :agent_contexts do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :session_id, null: false
      t.jsonb :state, default: {}
      t.jsonb :metadata, default: {}
      t.datetime :expires_at
      t.timestamps
    end
    add_index :agent_contexts, :session_id, unique: true
    add_index :agent_contexts, :expires_at

    # Fragments - cached context pieces for deterministic replay
    create_table :agent_fragments do |t|
      t.references :agent_context, null: false, foreign_key: true
      t.string :content_hash, null: false
      t.text :content, null: false
      t.string :fragment_type
      t.integer :token_count
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    add_index :agent_fragments, :content_hash
    add_index :agent_fragments, [ :agent_context_id, :content_hash ], unique: true

    # Reasons - deterministic references explaining why a fragment was used
    create_table :agent_reasons do |t|
      t.references :agent_fragment, null: false, foreign_key: true
      t.string :reason_type, null: false
      t.text :explanation
      t.float :confidence
      t.jsonb :evidence, default: []
      t.timestamps
    end
    add_index :agent_reasons, :reason_type
    add_index :agent_reasons, [ :agent_fragment_id, :reason_type ]
  end
end
