# One agentic pass over a hunt: what was searched, what the agent said, what
# it cost, and the trace that shows every step on the dashboard.
class DiscoveryRun < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze
  TRIGGERS = %w[manual scheduled].freeze
  SCORERS = %w[agent heuristic].freeze

  belongs_to :hunt
  belongs_to :user
  has_many :findings, dependent: :nullify
  has_one :charge, dependent: :nullify
  # The persisted agent conversation (solid_agent): messages, tool exchange,
  # generations, each carrying this run's trace id.
  has_many :agent_contexts, as: :contextable, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :scored_by, inclusion: { in: SCORERS }, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }
  scope :in_progress, -> { where(status: %w[queued running]) }

  STATUSES.each do |value|
    define_method(:"#{value}?") { status == value }
  end

  def in_progress?
    queued? || running?
  end

  def finished?
    completed? || failed?
  end

  def duration
    finished_at && started_at ? finished_at - started_at : nil
  end

  def total_tokens
    input_tokens + output_tokens
  end

  def query_list
    Array(queries).map(&:to_s)
  end

  def perform!
    Discovery::Pipeline.call(self)
  end
end
