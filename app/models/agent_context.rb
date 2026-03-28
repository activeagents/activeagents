# frozen_string_literal: true

class AgentContext < ApplicationRecord
  belongs_to :agent
  has_many :agent_fragments, dependent: :destroy
  has_many :agent_reasons, through: :agent_fragments

  validates :session_id, presence: true, uniqueness: true

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }

  before_validation :generate_session_id, on: :create

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def active?
    !expired?
  end

  # Add a fragment to this context, deduplicating by content hash
  def add_fragment(content:, type: "message", metadata: {})
    content_hash = Digest::SHA256.hexdigest(content)

    agent_fragments.find_or_create_by!(content_hash: content_hash) do |fragment|
      fragment.content = content
      fragment.fragment_type = type
      fragment.token_count = estimate_tokens(content)
      fragment.metadata = metadata
    end
  end

  # Look up a cached deterministic response for the given input
  def deterministic_response(input)
    input_hash = Digest::SHA256.hexdigest(input)
    fragment = agent_fragments.find_by(content_hash: input_hash)
    return nil unless fragment

    reason = fragment.agent_reasons
      .where(reason_type: "cached_generation")
      .order(confidence: :desc)
      .first

    reason&.evidence&.dig("cached_response")
  end

  # Store a generation result for deterministic replay
  def cache_generation(input:, output:, reason_type: "cached_generation")
    fragment = add_fragment(content: input, type: "generation_input")
    fragment.agent_reasons.create!(
      reason_type: reason_type,
      explanation: "Cached generation result",
      confidence: 1.0,
      evidence: { "cached_response" => output, "cached_at" => Time.current.iso8601 }
    )
    fragment
  end

  # Update session state
  def update_state(key, value)
    state[key.to_s] = value
    save!
  end

  def get_state(key)
    state[key.to_s]
  end

  private

  def generate_session_id
    self.session_id ||= SecureRandom.uuid
  end

  def estimate_tokens(content)
    # Rough estimate: ~4 characters per token
    (content.length / 4.0).ceil
  end
end
