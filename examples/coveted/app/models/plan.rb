# A pricing tier. Plans are configuration, not rows: config/plans.yml lists
# each tier's monthly price, the fee the product takes per discovery run,
# the schedule frequencies it unlocks and how many hunts may be active.
class Plan
  include Comparable

  PATH = Rails.root.join("config/plans.yml")

  attr_reader :key, :name, :tagline, :monthly_cents, :run_fee_cents, :frequencies,
              :max_active_hunts, :features, :position

  class << self
    def all
      @all ||= YAML.load_file(PATH).each_with_index.map { |(key, attrs), index| new(key, attrs, position: index) }
    end

    def keys
      all.map(&:key)
    end

    def find(key)
      find_by(key) || raise(ArgumentError, "Unknown plan: #{key.inspect}")
    end

    def find_by(key)
      all.find { |plan| plan.key == key.to_s }
    end

    # The plan a new account starts on: the first one in the file.
    def default
      all.first
    end

    def reload!
      @all = nil
    end
  end

  def initialize(key, attrs, position:)
    attrs = attrs.with_indifferent_access
    @key = key.to_s
    @name = attrs.fetch(:name)
    @tagline = attrs[:tagline].to_s
    @monthly_cents = attrs.fetch(:monthly_cents).to_i
    @run_fee_cents = attrs.fetch(:run_fee_cents).to_i
    @frequencies = Array(attrs.fetch(:frequencies)).map(&:to_s).freeze
    @max_active_hunts = attrs.fetch(:max_active_hunts).to_i
    @features = Array(attrs[:features]).map(&:to_s).freeze
    @position = position
  end

  def subscription?
    monthly_cents.positive?
  end

  def free_runs?
    run_fee_cents.zero?
  end

  def allows_frequency?(frequency)
    frequencies.include?(frequency.to_s)
  end

  # The most frequent schedule the plan allows; frequencies are listed
  # slowest to fastest.
  def fastest_frequency
    frequencies.last
  end

  def <=>(other)
    position <=> other.position
  end

  def ==(other)
    other.is_a?(Plan) && other.key == key
  end
  alias eql? ==

  def hash
    key.hash
  end

  def to_param
    key
  end
end
