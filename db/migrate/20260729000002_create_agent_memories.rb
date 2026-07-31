# frozen_string_literal: true

# Agent-curated long-term memory (solid_agent HasMemory contract): a
# summary list the model decides to read/write via save_memory /
# recall_memory tools. Scoped to (memorable, scope) — not agent class — so
# it doubles as a handoff channel between agents sharing a subject.
class CreateAgentMemories < ActiveRecord::Migration[8.2]
  def change
    create_table :agent_memories do |t|
      t.references :memorable, polymorphic: true, index: true
      t.string :scope, null: false, default: "default"
      t.timestamps
    end
    add_index :agent_memories, [ :memorable_type, :memorable_id, :scope ], unique: true

    create_table :agent_memory_entries do |t|
      t.references :agent_memory, null: false, foreign_key: true
      t.text :content, null: false
      t.string :source_agent
      t.string :category
      t.timestamps
    end
    add_index :agent_memory_entries, [ :agent_memory_id, :created_at ]
    add_index :agent_memory_entries, :category
  end
end
