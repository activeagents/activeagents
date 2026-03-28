# frozen_string_literal: true

class AgentInstruction < ApplicationRecord
  belongs_to :agent

  SCOPES = %w[system user context].freeze

  validates :name, presence: true, uniqueness: { scope: :agent_id }
  validates :content, presence: true
  validates :scope, inclusion: { in: SCOPES }

  scope :by_scope, ->(scope) { where(scope: scope) }
  scope :ordered, -> { order(priority: :desc) }
  scope :system_instructions, -> { by_scope("system").ordered }

  # Compose all instructions for an agent into a single string
  def self.compose(separator: "\n\n")
    ordered.pluck(:content).join(separator)
  end
end
