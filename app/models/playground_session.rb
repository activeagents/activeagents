class PlaygroundSession < ApplicationRecord
  has_many :playground_messages, -> { order(:position) }, dependent: :destroy

  validates :session_token, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[active completed failed] }

  scope :active, -> { where(status: "active") }

  def add_message(role:, content:, agent_name: nil, metadata: {})
    pos = playground_messages.maximum(:position).to_i + 1
    playground_messages.create!(
      role: role,
      content: content,
      agent_name: agent_name,
      position: pos,
      metadata: metadata
    )
  end

  def update_shared_context(key, value)
    self.shared_context[key.to_s] = value
    save!
  end

  def research_findings
    shared_context["research"] || {}
  end

  def draft_content
    shared_context["draft"]
  end

  def report_content
    shared_context["report"]
  end

  def messages_for_agent(agent_name)
    playground_messages.where(agent_name: [agent_name, nil])
  end
end
