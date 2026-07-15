class Account < ApplicationRecord
  pay_customer stripe_attributes: :stripe_attributes

  belongs_to :owner, class_name: "User", inverse_of: :owned_accounts
  delegate :email_address, to: :owner
  alias_method :email, :email_address
  has_many :account_memberships, dependent: :destroy
  has_many :members, through: :account_memberships, source: :user
  has_many :telemetry_traces, dependent: :delete_all

  # Bearer token used by the activeagent gem's telemetry reporter to push
  # traces to POST /v1/traces (ActiveAgent::Dashboard::Api::TracesController).
  has_secure_token :telemetry_api_key, length: 36

  validates :name, presence: true

  # Agent execution limits per monthly period, by plan slug.
  # Pro matches the advertised 10,000 executions/month on the pricing page.
  USAGE_LIMITS = {
    "free" => 100,
    "pro" => 10_000,
    "enterprise" => -1 # Unlimited
  }.freeze

  # Telemetry trace ingestion limits by plan (traces per monthly period)
  TRACE_LIMITS = {
    "free" => 1_000,
    "pro" => 25_000,
    "enterprise" => -1 # Unlimited
  }.freeze

  def stripe_attributes(pay_customer)
    {
      metadata: {
        account_id: id,
        account_name: name
      }
    }
  end

  def active_subscription
    pay_customers.flat_map(&:subscriptions).find(&:active?)
  end

  def subscribed?
    active_subscription.present?
  end

  def current_plan
    if active_subscription
      stripe_price_id = active_subscription.processor_plan
      Plan.find_by(stripe_monthly_price_id: stripe_price_id) ||
        Plan.find_by(stripe_annual_price_id: stripe_price_id)
    else
      # Default to free plan for users without a subscription
      Plan.free.first
    end
  end

  # Usage tracking methods
  def reset_usage_period_if_needed!
    period_start = usage_period_start || created_at
    if period_start < 1.month.ago
      update!(
        agent_runs_this_period: 0,
        usage_period_start: Time.current.beginning_of_month
      )
    end
  end

  def increment_agent_runs!
    reset_usage_period_if_needed!
    increment!(:agent_runs_this_period)
  end

  def agent_runs_remaining
    limit = effective_agent_runs_limit
    return Float::INFINITY if limit == -1
    [ limit - agent_runs_this_period, 0 ].max
  end

  def can_run_agent?
    limit = effective_agent_runs_limit
    return true if limit == -1  # Unlimited
    agent_runs_this_period < limit
  end

  def effective_agent_runs_limit
    plan_slug = current_plan&.slug || "free"
    USAGE_LIMITS[plan_slug] || USAGE_LIMITS["free"]
  end

  def usage_stats
    {
      runs_used: agent_runs_this_period,
      runs_limit: effective_agent_runs_limit,
      runs_remaining: agent_runs_remaining,
      can_run: can_run_agent?,
      period_start: usage_period_start&.iso8601,
      plan: current_plan&.slug || "free",
      traces_used: telemetry_traces_this_period,
      traces_limit: effective_trace_limit,
      tokens_used: telemetry_tokens_this_period
    }
  end

  # -- Telemetry trace quota -------------------------------------------------

  def effective_trace_limit
    plan_slug = current_plan&.slug || "free"
    TRACE_LIMITS[plan_slug] || TRACE_LIMITS["free"]
  end

  def telemetry_traces_this_period
    telemetry_traces.where(timestamp: (usage_period_start || created_at)..).count
  end

  def telemetry_tokens_this_period
    telemetry_traces.where(timestamp: (usage_period_start || created_at)..)
      .sum("total_input_tokens + total_output_tokens + total_thinking_tokens")
  end

  def can_ingest_traces?
    limit = effective_trace_limit
    return true if limit == -1
    telemetry_traces_this_period < limit
  end

  # Called by ActiveAgent::Dashboard::Api::TracesController on every
  # authenticated ingest request (rate-limit hook).
  def increment_telemetry_usage!
    reset_usage_period_if_needed!
  end
end
