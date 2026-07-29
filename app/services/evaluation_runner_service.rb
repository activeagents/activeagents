# frozen_string_literal: true

# Runs an Evaluation against the agent's most recent persisted generations
# (solid_agent's agent_generations).
#
# Rule-based criteria are scored deterministically from the recorded data.
# The llm_judge criterion asks a judge model (through the activeagent gem)
# to score each sample 0.0..1.0; it requires configured provider
# credentials and is skipped — never faked — when none are available.
class EvaluationRunnerService
  PASS_THRESHOLD = 0.7

  def self.call(evaluation)
    new(evaluation).call
  end

  def initialize(evaluation)
    @evaluation = evaluation
  end

  def call
    run = @evaluation.evaluation_runs.create!(status: :running)

    samples = sample_generations
    if samples.empty?
      run.update!(
        status: :failed,
        error_message: "No generations to evaluate yet — run the agent first",
        completed_at: Time.current
      )
      return run
    end

    scores = {}
    per_sample_scores = Hash.new { |h, k| h[k] = [] }

    @evaluation.criteria.each do |criterion|
      sample_scores = samples.map { |generation| score_sample(criterion, generation) }

      # nil means the criterion could not be scored (e.g. llm_judge without
      # provider credentials); it is reported as skipped, not zero.
      scored = sample_scores.compact
      if scored.empty?
        scores[criterion["key"]] = { "skipped" => true, "reason" => skip_reason(criterion) }
        next
      end

      samples.each_with_index do |generation, index|
        per_sample_scores[generation.id] << sample_scores[index] if sample_scores[index]
      end

      scores[criterion["key"]] = {
        "score" => (scored.sum / scored.size).round(3),
        "min" => scored.min.round(3),
        "max" => scored.max.round(3),
        "passed" => scored.count { |s| s >= PASS_THRESHOLD },
        "total" => scored.size
      }
    end

    samples_passed = per_sample_scores.count do |_id, values|
      values.any? && values.all? { |s| s >= PASS_THRESHOLD }
    end

    run.update!(
      status: :complete,
      scores: scores,
      samples_evaluated: samples.size,
      samples_passed: samples_passed,
      completed_at: Time.current
    )
    run
  rescue StandardError => e
    run&.update!(status: :failed, error_message: e.message, completed_at: Time.current)
    raise
  end

  private

  def sample_generations
    AgentGeneration
      .joins(:agent_context)
      .where(agent_contexts: { contextable: @evaluation.agent })
      .order(created_at: :desc)
      .limit(@evaluation.sample_size)
      .to_a
  end

  # Returns 0.0..1.0, or nil when the criterion cannot be scored.
  def score_sample(criterion, generation)
    config = criterion["config"] || {}

    case criterion["type"]
    when "response_present"
      generation.content.present? ? 1.0 : 0.0
    when "min_length"
      min = config.fetch("chars", 40).to_i
      length = generation.content.to_s.length
      [ length.to_f / min, 1.0 ].min
    when "max_latency_ms"
      budget = config.fetch("ms", 5_000).to_f
      duration_ms = generation.duration_seconds.to_f * 1000
      return 1.0 if duration_ms.zero? # duration not recorded
      duration_ms <= budget ? 1.0 : [ budget / duration_ms, 1.0 ].min
    when "token_budget"
      budget = config.fetch("output_tokens", 1_000).to_f
      tokens = generation.output_tokens.to_f
      tokens <= budget ? 1.0 : [ budget / tokens, 1.0 ].min
    when "contains"
      matches_pattern?(generation.content, config) ? 1.0 : 0.0
    when "not_contains"
      matches_pattern?(generation.content, config) ? 0.0 : 1.0
    when "llm_judge"
      llm_judge_score(criterion, generation)
    end
  end

  def matches_pattern?(content, config)
    pattern = config["pattern"].to_s
    return false if pattern.blank?

    content.to_s.match?(Regexp.new(pattern, Regexp::IGNORECASE))
  rescue RegexpError
    content.to_s.downcase.include?(pattern.downcase)
  end

  # --- LLM judge -----------------------------------------------------------

  def llm_judge_score(criterion, generation)
    return nil unless judge_available?
    return nil if generation.content.blank?

    response = judge_class.prompt(
      message: judge_prompt(criterion, generation),
      instructions: "You are an impartial evaluation judge. Respond ONLY with JSON: {\"score\": <float between 0.0 and 1.0>}"
    ).generate_now

    parse_judge_score(response.message&.content)
  rescue StandardError => e
    Rails.logger.error("[EvaluationRunnerService] Judge error: #{e.class} - #{e.message}")
    nil
  end

  def judge_prompt(criterion, generation)
    <<~PROMPT
      Criterion: #{criterion.dig('config', 'prompt').presence || criterion['key'].to_s.humanize}

      Agent output to evaluate:
      ---
      #{generation.content.to_s.truncate(4_000)}
      ---

      Score the output against the criterion from 0.0 (fails completely) to 1.0 (fully satisfies).
      Respond only with JSON: {"score": <float>}
    PROMPT
  end

  def parse_judge_score(content)
    match = content.to_s.match(/"score"\s*:\s*(\d+(?:\.\d+)?)/)
    return nil unless match

    match[1].to_f.clamp(0.0, 1.0)
  end

  # The judge needs real provider credentials; scoring with the mock
  # provider would fabricate results.
  def judge_available?
    judge_provider.present?
  end

  def judge_provider
    @judge_provider ||=
      %i[anthropic openai openrouter].find do |name|
        account_provider_key(name).present? || global_provider_token?(name)
      end || (:ollama if account_provider_key(:ollama).present?)
  end

  def global_provider_token?(name)
    config = ActiveAgent.configuration[name]
    config.respond_to?(:[]) && config[:access_token].present?
  end

  # The evaluated agent owner's stored provider key (Settings -> Provider
  # API Keys); preferred over the platform's ENV credentials for the judge.
  def account_provider_key(name)
    account&.provider_key_for(name)
  end

  def account
    @account ||= @evaluation.agent.user&.primary_account
  end

  def judge_class
    provider = judge_provider
    model = @evaluation.judge_model.presence
    options = {}
    options[:model] = model if model
    if (account_key = account_provider_key(provider))
      options.merge!(account_key.generation_options)
    end

    @judge_class ||= Class.new(ActiveAgent::Base) do
      define_singleton_method(:name) { "EvaluationJudgeAgent" }
      generate_with provider, **options
    end
  end

  def skip_reason(criterion)
    if criterion["type"] == "llm_judge"
      "LLM judge requires provider credentials (add a provider API key in Settings or set ANTHROPIC_API_KEY / OPENAI_API_KEY)"
    else
      "No scorable samples"
    end
  end
end
