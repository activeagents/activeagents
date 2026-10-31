# A listing the agent (or the heuristic fallback) judged worth a collector's
# attention. One row per listing URL per hunt, so re-running a hunt only adds
# listings the collector has not seen.
class Finding < ApplicationRecord
  VERDICTS = %w[grail strong maybe pass].freeze
  STATUSES = %w[new saved dismissed].freeze
  SCORERS = %w[agent heuristic].freeze

  # TUI-style glyphs, in the dashboard's style.
  GLYPHS = { "grail" => "[*]", "strong" => "[+]", "maybe" => "[?]", "pass" => "[-]" }.freeze

  belongs_to :hunt
  belongs_to :user
  belongs_to :discovery_run, optional: true

  validates :title, presence: true
  validates :url, presence: true, uniqueness: { scope: :hunt_id },
                  format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a web address" }
  validates :match_score, numericality: { only_integer: true, in: 0..100 }, allow_nil: true
  validates :verdict, inclusion: { in: VERDICTS }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validates :scored_by, inclusion: { in: SCORERS }

  scope :by_score, -> { order(match_score: :desc, created_at: :desc) }
  scope :fresh, -> { where(status: "new") }
  scope :saved, -> { where(status: "saved") }
  scope :dismissed, -> { where(status: "dismissed") }

  STATUSES.each do |value|
    define_method(:"#{value}?") { status == value }
  end

  def mark_saved!
    update!(status: "saved")
  end

  def dismiss!
    update!(status: "dismissed")
  end

  def red_flag_list
    Array(red_flags).map(&:to_s)
  end

  def glyph
    GLYPHS.fetch(verdict.to_s, "[ ]")
  end

  def scored_by_agent?
    scored_by == "agent"
  end
end
