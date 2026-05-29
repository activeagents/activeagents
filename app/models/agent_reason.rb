# frozen_string_literal: true

class AgentReason < ApplicationRecord
  belongs_to :agent_fragment

  REASON_TYPES = %w[
    semantic_match
    tool_result
    user_preference
    business_rule
    cached_generation
  ].freeze

  validates :reason_type, presence: true, inclusion: { in: REASON_TYPES }

  scope :by_type, ->(type) { where(reason_type: type) }
  scope :high_confidence, -> { where("confidence >= ?", 0.8) }

  # Create a reason for a fragment
  def self.for_fragment(fragment, type:, explanation:, evidence: {})
    create!(
      agent_fragment: fragment,
      reason_type: type,
      explanation: explanation,
      evidence: evidence,
      confidence: calculate_confidence(type, evidence)
    )
  end

  # Apply this reason to determine the generation output
  def apply
    case reason_type
    when "cached_generation"
      evidence&.dig("cached_response")
    when "tool_result"
      evidence&.dig("tool_output")
    when "semantic_match"
      agent_fragment.content
    end
  end

  private

  def self.calculate_confidence(type, evidence)
    case type
    when "cached_generation"
      1.0 # Exact cache hits are fully confident
    when "tool_result"
      0.95 # Tool results are highly reliable
    when "business_rule"
      0.9
    when "user_preference"
      0.85
    when "semantic_match"
      evidence&.dig("similarity_score") || 0.8
    else
      0.5
    end
  end
end
