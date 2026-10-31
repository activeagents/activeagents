# What a collector is looking for, and how often the agent should look.
#
# A hunt is the brief the agents read (title, brand, keywords, sizes, budget,
# condition) plus a schedule. Each time it runs, a DiscoveryRun records what
# the agent did and the Findings it recorded.
class Hunt < ApplicationRecord
  FREQUENCIES = {
    "manual" => nil,
    "weekly" => 1.week,
    "daily" => 1.day,
    "every_6_hours" => 6.hours,
    "hourly" => 1.hour
  }.freeze

  FREQUENCY_LABELS = {
    "manual" => "Only when I ask",
    "weekly" => "Every week",
    "daily" => "Every day",
    "every_6_hours" => "Every 6 hours",
    "hourly" => "Every hour"
  }.freeze

  STATUSES = %w[active paused].freeze
  CONDITIONS = %w[any new used vintage].freeze
  CATEGORIES = %w[clothing footwear watches cameras audio bags keyboards vinyl homeware design games outdoor other].freeze
  CURRENCIES = %w[USD EUR GBP JPY CAD AUD].freeze

  belongs_to :user
  has_many :discovery_runs, dependent: :destroy
  has_many :findings, dependent: :destroy

  validates :title, presence: true, length: { maximum: 120 }
  validates :frequency, inclusion: { in: FREQUENCIES.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :condition, inclusion: { in: CONDITIONS }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :max_price_cents, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :frequency_allowed_by_plan, if: :user
  validate :within_plan_hunt_cap, on: :create, if: :user

  scope :active, -> { where(status: "active") }
  scope :recent, -> { order(updated_at: :desc) }
  # Scheduled hunts whose next run time has passed.
  scope :due, -> { active.where.not(frequency: "manual").where(next_run_at: ..Time.current) }

  before_save :schedule_next_run, if: -> { new_record? || frequency_changed? || status_changed? }

  def active?
    status == "active"
  end

  def paused?
    status == "paused"
  end

  def interval
    FREQUENCIES[frequency]
  end

  def scheduled?
    interval.present?
  end

  def frequency_label
    FREQUENCY_LABELS.fetch(frequency, frequency)
  end

  # The budget as a decimal amount, for forms.
  def max_price
    max_price_cents && max_price_cents / 100.0
  end

  def max_price=(value)
    self.max_price_cents = value.blank? ? nil : (value.to_s.delete(",").to_f * 100).round
  end

  def keyword_list
    split_list(keywords)
  end

  def size_list
    split_list(sizes)
  end

  # The brief the agents read. Also shown on the hunt page, so a collector
  # sees exactly what the agent was told.
  def brief
    lines = [ "Looking for: #{title}" ]
    lines << "Brand: #{brand}" if brand.present?
    lines << "Category: #{category}" if category.present?
    lines << "Details: #{description.squish}" if description.present?
    lines << "Keywords: #{keyword_list.join(', ')}" if keyword_list.any?
    lines << "Sizes that fit: #{size_list.join(', ')}" if size_list.any?
    lines << "Budget: up to #{format_budget}" if max_price_cents
    lines << "Condition: #{condition == 'any' ? 'any condition' : condition}"
    lines.join("\n")
  end

  # The queries the pipeline runs before the agent takes over: the planner
  # agent's plan when one has been generated, otherwise derived from the brief.
  def search_queries
    planned = Array(search_plan&.dig("queries")).map(&:to_s).map(&:squish).reject(&:blank?)
    planned.presence || derived_queries
  end

  def derived_queries
    base = [ brand, title ].compact_blank.map(&:squish)
    base = [ title.squish ] if brand.present? && title.downcase.include?(brand.downcase)
    queries = [ base.join(" ") ]
    keyword_list.first(3).each { |keyword| queries << [ brand, keyword ].compact_blank.join(" ") }
    queries.map(&:squish).reject(&:blank?).uniq.first(4)
  end

  def known_urls
    findings.pluck(:url)
  end

  # Queues a discovery run. The fee is fixed when the run is created, at the
  # rate of the plan the collector is on right then.
  def run_now!(trigger: "manual")
    run = discovery_runs.create!(user: user, trigger: trigger, fee_cents: user.plan.run_fee_cents)
    push_schedule!(from: Time.current) if trigger == "scheduled"
    DiscoveryRunJob.perform_later(run)
    run
  end

  # Called by the pipeline when a run finishes, however it finished.
  def mark_ran!(at: Time.current)
    update_columns(last_run_at: at, next_run_at: next_run_from(at))
  end

  # Asks the planner agent for search queries and keeps them. Returns the
  # plan, or the structured error the delegation hands back when the model's
  # answer did not fit the declared schema (every answer from the mock
  # provider, which cannot produce JSON).
  def plan!
    result = HunterAgent.new.plan_queries(brief: brief)
    result = result.with_indifferent_access if result.is_a?(Hash)

    if result.is_a?(Hash) && Array(result[:queries]).any?
      update!(search_plan: result.slice(:queries, :negative_keywords, :sources, :notes).to_h)
      { ok: true, plan: search_plan }
    else
      { ok: false, error: (result.is_a?(Hash) && result[:error]) || "no plan returned" }
    end
  end

  private

  def split_list(value)
    value.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?)
  end

  def format_budget
    amount = max_price_cents / 100.0
    "#{amount % 1 == 0 ? amount.to_i : amount} #{currency}"
  end

  def schedule_next_run
    self.next_run_at = next_run_from(Time.current)
  end

  def push_schedule!(from:)
    update_columns(next_run_at: next_run_from(from))
  end

  def next_run_from(time)
    active? && interval ? time + interval : nil
  end

  def frequency_allowed_by_plan
    return if user.plan.allows_frequency?(frequency)

    errors.add(:frequency, "#{frequency_label.downcase} hunts aren't included in the #{user.plan.name} plan")
  end

  def within_plan_hunt_cap
    return unless active? && user.active_hunt_cap_reached?

    errors.add(:base, "The #{user.plan.name} plan allows #{user.plan.max_active_hunts} active hunts. Pause one, or upgrade.")
  end
end
