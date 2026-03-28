# frozen_string_literal: true

class AgentToolset < ApplicationRecord
  belongs_to :agent

  validates :name, presence: true, uniqueness: { scope: :agent_id }

  scope :enabled, -> { where(enabled: true) }

  # Returns all tool names across enabled toolsets for an agent
  def self.resolved_tools
    enabled.flat_map { |ts| ts.tools }.uniq
  end

  # Returns tool definitions from the ToolRegistry for this toolset
  def tool_definitions
    ToolRegistry.definitions_for(tools)
  end
end
