# frozen_string_literal: true

class CreateAgentMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_messages do |t|
      t.references :agent_context, null: false, foreign_key: true, index: true

      # Message role: user, assistant, system, tool
      t.string :role, null: false

      # Message content (text content for the message)
      t.text :content

      # For tool calls and results
      t.string :tool_call_id
      t.string :tool_name
      t.json :tool_arguments, default: {}
      t.json :tool_result

      # For multimodal content (images, files)
      t.json :attachments, default: []

      # Metadata
      t.json :metadata, default: {}

      # Provenance snapshot + content checksum, populated automatically by
      # SolidAgent::HasContext when present
      t.json :provenance, default: {}
      t.string :content_checksum

      t.timestamps
    end

    add_index :agent_messages, :role
    add_index :agent_messages, :tool_call_id
    add_index :agent_messages, [:agent_context_id, :created_at]
  end
end
