# frozen_string_literal: true

class CreateAgentTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_templates do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :category # productivity, development, research, creative, data

      # Template configuration (same as agents)
      t.string :provider, default: "openai"
      t.string :model, default: "gpt-4o-mini"
      t.text :instructions
      t.string :preset_type
      t.jsonb :appearance, default: {}
      t.jsonb :instruction_sets, default: []
      t.jsonb :tools, default: []
      t.jsonb :model_config, default: {}

      # Metadata
      t.string :icon
      t.integer :usage_count, default: 0
      t.boolean :featured, default: false
      t.boolean :public, default: true

      t.timestamps
    end

    add_index :agent_templates, :slug, unique: true
    add_index :agent_templates, :category
    add_index :agent_templates, :featured
    add_index :agent_templates, :usage_count
  end
end
