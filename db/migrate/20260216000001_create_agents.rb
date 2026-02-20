# frozen_string_literal: true

class CreateAgents < ActiveRecord::Migration[8.0]
  def change
    create_table :agents do |t|
      t.string :name, null: false
      t.text :description
      t.string :slug, null: false

      # Agent class configuration
      t.string :agent_class_name
      t.string :provider, default: "openai"
      t.string :model, default: "gpt-4o-mini"

      # Instructions and system prompt
      t.text :instructions

      # Avatar/appearance configuration
      t.string :preset_type # terminal, webDeveloper, research, etc.
      t.jsonb :appearance, default: {} # { hat, hatAccessory, heldItem, theme, customColors }

      # Capabilities
      t.jsonb :instruction_sets, default: [] # ["github", "ruby", "rails", ...]
      t.jsonb :tools, default: [] # ["terminal", "playwright", "filesystem", ...]
      t.jsonb :mcp_servers, default: [] # MCP server configurations

      # Model configuration
      t.jsonb :model_config, default: {} # { temperature, max_tokens, etc. }

      # Response format
      t.jsonb :response_format, default: {} # { type: "json_schema", schema: {...} }

      # Status
      t.integer :status, default: 0, null: false # 0: draft, 1: active, 2: archived

      t.timestamps
    end

    add_index :agents, :slug, unique: true
    add_index :agents, :status
    add_index :agents, :provider
  end
end
