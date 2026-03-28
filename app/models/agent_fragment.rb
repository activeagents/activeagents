# frozen_string_literal: true

class AgentFragment < ApplicationRecord
  belongs_to :agent_context
  has_many :agent_reasons, dependent: :destroy

  validates :content_hash, presence: true, uniqueness: { scope: :agent_context_id }
  validates :content, presence: true

  FRAGMENT_TYPES = %w[message generation_input generation_output tool_result system].freeze

  validates :fragment_type, inclusion: { in: FRAGMENT_TYPES }, allow_nil: true

  scope :by_type, ->(type) { where(fragment_type: type) }
  scope :with_reasons, -> { joins(:agent_reasons).distinct }

  before_validation :compute_content_hash, if: -> { content_hash.blank? && content.present? }

  # Check if this fragment has a deterministic reason attached
  def deterministic?
    agent_reasons.where(reason_type: "cached_generation").exists?
  end

  # Get the cached response if this is a deterministic fragment
  def cached_response
    reason = agent_reasons.where(reason_type: "cached_generation").order(confidence: :desc).first
    reason&.evidence&.dig("cached_response")
  end

  private

  def compute_content_hash
    self.content_hash = Digest::SHA256.hexdigest(content)
  end
end
