class PlaygroundMessage < ApplicationRecord
  belongs_to :playground_session

  validates :role, presence: true, inclusion: { in: %w[user assistant system tool] }
  validates :position, presence: true

  scope :ordered, -> { order(:position) }

  def to_h
    {
      id: id,
      role: role,
      agent_name: agent_name,
      content: content,
      position: position,
      metadata: metadata,
      created_at: created_at
    }
  end
end
