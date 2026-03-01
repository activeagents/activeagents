# frozen_string_literal: true

class AddFreeTierAndMcpServersToAgentTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column :agent_templates, :free_tier, :boolean, default: false
    add_column :agent_templates, :mcp_servers, :jsonb, default: {}

    add_index :agent_templates, :free_tier
  end
end
