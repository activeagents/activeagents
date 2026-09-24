# frozen_string_literal: true

require "digest"

# Used to store an evaluation an application ran itself, published as the
# version-1 envelope ActiveAgent::Evals::Publisher sends, in the dashboard
# engine's own evaluation tables — so the Evaluations view shows it the way it
# shows a run the dashboard executed. It never executes the application's agent.
#
# The report lands as:
#   agent      — the account owner's observed agent for the envelope's
#                `source` and `agent_name`
#   evaluation — that agent's evaluation named for the `suite` and the report's
#                scope (SCOPE_KEYS in its metadata)
#   scenarios  — one per reported scenario key, updated to the reported prompt
#   run        — one complete EvaluationRun per (account, run_id), with one
#                ActionAgent::EvaluationScenarioResult per scenario and model
#
# An identical retry returns the stored run. Different content under a run_id
# already stored raises Conflict. The account lock and the unique index on
# (account_id, external_run_id) make concurrent retries converge on one run.
class ExternalEvaluationImport
  class Invalid < StandardError; end
  class Conflict < StandardError; end

  MAX_BYTES = 2.megabytes
  MAX_RESULTS = 1000
  MAX_MODELS = 50
  ID_PATTERN = %r{\A[a-zA-Z0-9_.:/-]{1,200}\z}
  TRACE_PATTERN = /\A[a-zA-Z0-9_-]{1,128}\z/
  STATUSES = %w[passed failed errored].freeze
  # Report metadata that tells one evaluation of a suite from another, in the
  # order it is written into the evaluation's name.
  SCOPE_KEYS = %w[scope environment role].freeze
  # The engine stores at most this much of an answer (ScenarioEvaluationRunner#persist).
  OUTPUT_BYTES = 20_000

  # Returns `[run, duplicate]`: the stored EvaluationRun, and whether it was
  # already stored by an earlier identical delivery.
  def self.call(account:, payload:)
    new(account, payload).call
  end

  def initialize(account, payload)
    @account = account
    @payload = payload
  end

  def call
    validate!
    digest = Digest::SHA256.hexdigest(JSON.generate(canonical(@payload)))

    @account.with_lock do
      existing = EvaluationRun.find_by(account_id: @account.id, external_run_id: @payload["run_id"])
      if existing
        raise Conflict, "run_id already exists with a different report" unless existing.external_report_digest == digest

        [ existing, true ]
      else
        [ import(digest), false ]
      end
    end
  end

  private

  def report
    @payload["report"]
  end

  def results
    report["results"]
  end

  def metadata
    report["metadata"] || {}
  end

  def import(digest)
    evaluation = find_or_initialize_evaluation(find_or_create_agent)
    scenarios = upsert_scenarios(evaluation)
    run = evaluation.evaluation_runs.create!(
      account_id: @account.id,
      external_run_id: @payload["run_id"],
      external_report_digest: digest,
      status: :complete,
      selection: selection,
      scores: scores,
      samples_evaluated: results.size,
      samples_passed: results.count { |result| result["status"] == "passed" },
      completed_at: Time.current
    )
    results.each { |result| persist(run, scenarios.fetch(result["scenario_key"]), result) }
    evaluation.touch
    run
  end

  # --- records ---------------------------------------------------------------

  # Keyed with no action, unlike the per-action agents trace ingest observes:
  # the report evaluates the agent as a whole.
  def find_or_create_agent
    owner = @account.owner
    identity = { service_name: @payload["source"], agent_class_name: @payload["agent_name"], action_name: nil }
    Agent.for_owner(owner).observed_agents.find_by(identity) || begin
      agent = Agent.new(
        identity.merge(
          name: @payload["agent_name"],
          slug: agent_slug,
          status: :observed,
          source: "evaluation-report",
          description: "Evaluation reports published by #{@payload['source']}",
          provider: results.first["provider"],
          model: results.first["model"],
          instructions: "",
          tools: []
        )
      )
      agent.owner = owner
      agent.save!
      agent
    end
  end

  def agent_slug
    base = [ @payload["source"], @payload["agent_name"] ].join("-").parameterize
    return base unless Agent.exists?(slug: base)

    "#{base}-#{SecureRandom.hex(3)}"
  end

  def find_or_initialize_evaluation(agent)
    evaluation = agent.evaluations.find_or_initialize_by(name: evaluation_name)
    return evaluation unless evaluation.new_record?

    evaluation.assign_attributes(
      judge_kind: judge_label ? "llm" : "rules",
      judge_model: judge_label,
      criteria: [],
      config: { "external" => { "source" => @payload["source"], "suite" => @payload["suite"], "scope" => scope } }
    )
    evaluation
  end

  # "orders (eu, support)" for a report whose metadata names a scope and a
  # role; the bare suite for one with no scope.
  def evaluation_name
    values = scope.values
    values.empty? ? @payload["suite"] : "#{@payload['suite']} (#{values.join(', ')})"
  end

  def scope
    SCOPE_KEYS.filter_map { |key| [ key, metadata[key] ] if metadata[key].is_a?(String) && metadata[key].present? }.to_h
  end

  # The judge that scored the report, or nil when it was scored on rules alone.
  # The framework's pass-rate ranking names itself as the judge of a verdict no
  # model wrote, which is not a judge.
  def judge_label
    label = report["judge"]
    label if label.present? && label != ActiveAgent::Evals::Report::PASS_RATE_JUDGE
  end

  # Adds the scenarios the evaluation lacks and updates each reported one to
  # the prompt and group it ran with. Scenarios the report did not run are left
  # as they are. Returns every reported scenario by key.
  def upsert_scenarios(evaluation)
    by_key = evaluation.new_record? ? {} : evaluation.scenarios.index_by(&:key)
    next_position = by_key.values.filter_map(&:position).max&.succ || 0

    reported_scenarios.each do |attributes|
      unless by_key.key?(attributes["key"])
        by_key[attributes["key"]] = evaluation.scenarios.build(key: attributes["key"], position: next_position)
        next_position += 1
      end
      by_key[attributes["key"]].assign_attributes(prompt: attributes["prompt"], group: attributes["group"])
    end
    # A new evaluation is valid without criteria only once it has scenarios, so
    # it is saved with them; an existing one saves the scenarios it gained.
    evaluation.save!
    by_key.each_value { |scenario| scenario.save! if scenario.changed? }
    by_key
  end

  def reported_scenarios
    @reported_scenarios ||= results.uniq { |result| result["scenario_key"] }.map do |result|
      { "key" => result["scenario_key"], "prompt" => result["prompt"].presence || result["scenario_key"], "group" => result["group"] }
    end
  end

  def persist(run, scenario, result)
    run.scenario_results.create!(
      scenario: scenario,
      model: result["model"],
      provider: result["provider"],
      status: result["status"],
      score: result["score"],
      scores: result["scores"] || {},
      output: result["answer"].to_s.byteslice(0, OUTPUT_BYTES).to_s.scrub.presence,
      tool_calls: result["tool_calls"] || [],
      duration_ms: result["duration_ms"],
      input_tokens: result["input_tokens"],
      output_tokens: result["output_tokens"],
      cost: result["cost"],
      fault: result["fault"],
      recommendation: result["recommendation"],
      diagnosis: (result["diagnosis"] || {}).merge(
        "_replay_metadata" => result["metadata"] || {},
        "_scenario_snapshot" => {
          "key" => result["scenario_key"], "group" => result["group"], "prompt" => result["prompt"], "expectations" => {}
        }
      ),
      error_message: result["error"]
    )
  end

  # The scenarios and models the run covered, in the shape
  # ScenarioEvaluationRunner records, so EvaluationRun#to_report labels each
  # model the way the report did.
  def selection
    {
      "scenario_keys" => reported_scenarios.map { |scenario| scenario["key"] },
      "models" => results.uniq { |result| result["label"] }.map { |result| result.slice("label", "provider", "model") }
    }
  end

  # The run's scores in the shape the Evaluations view renders
  # (ScenarioEvaluationRunner#scores_for): the criterion scores, plus the
  # report's per-model summary, recommendations, verdict and metadata under
  # underscore-prefixed keys.
  def scores
    (report["criteria"] || {}).reject { |key, _| key.start_with?("_") }.merge(
      "_models" => report["models"],
      "_recommendations" => report["recommendations"] || [],
      "_verdict" => report["verdict"],
      "_selection" => selection,
      "_metadata" => metadata,
      "_judge_label" => report["judge"]
    ).compact
  end

  # --- validation ------------------------------------------------------------

  def validate!
    object!(@payload, "payload")
    validate_json!(@payload)
    raise Invalid, "version must be 1" unless @payload["version"] == 1

    %w[run_id source suite].each { |key| identifier!(@payload[key], key) }
    string!(@payload["agent_name"], "agent_name", 100, required: true)
    raise Invalid, "agent_name must contain at least two characters" if @payload["agent_name"].strip.length < 2

    object!(report, "report")
    optional_object!(report["metadata"], "report.metadata")
    optional_object!(report["criteria"], "report.criteria")
    optional_object!(report["verdict"], "report.verdict")
    raise Invalid, "report.recommendations must be an array" unless report["recommendations"].nil? || report["recommendations"].is_a?(Array)

    judge_trace_ids!(metadata["judge_trace_ids"])
    string!(report["judge"], "report.judge", 200)
    object!(report["models"], "report.models")
    raise Invalid, "report.models must contain 1-#{MAX_MODELS} models" unless report["models"].size.between?(1, MAX_MODELS)
    unless results.is_a?(Array) && results.size.between?(1, MAX_RESULTS)
      raise Invalid, "report.results must contain 1-#{MAX_RESULTS} results"
    end

    validate_results!
  end

  def validate_results!
    pairs = Set.new
    result_ids = Set.new
    results.each_with_index do |result, index|
      object!(result, "result #{index}")
      %w[scenario_key label provider model].each { |key| string!(result[key], "result.#{key}", 200, required: true) }
      raise Invalid, "result label #{result['label']} is missing from report.models" unless report["models"].key?(result["label"])
      raise Invalid, "duplicate scenario/model result" unless pairs.add?(result.values_at("scenario_key", "label"))
      raise Invalid, "invalid result status" unless STATUSES.include?(result["status"])
      unless result["fault"].nil? || ActionAgent::EvaluationScenarioResult::FAULTS.include?(result["fault"])
        raise Invalid, "unknown fault #{result['fault']}"
      end

      numeric!(result["score"], "result.score", max: 1)
      optional_object!(result["scores"], "result.scores")
      (result["scores"] || {}).each_value { |score| numeric!(score, "criterion score", max: 1) }
      %w[duration_ms cost input_tokens output_tokens].each { |key| numeric!(result[key], "result.#{key}") }
      %w[prompt answer error recommendation].each { |key| string!(result[key], "result.#{key}", 100_000) }
      string!(result["group"], "result.group", 200)
      raise Invalid, "result.tool_calls must be an array" unless result["tool_calls"].nil? || result["tool_calls"].is_a?(Array)

      optional_object!(result["diagnosis"], "result.diagnosis")
      optional_object!(result["metadata"], "result.metadata")
      result_metadata = result["metadata"] || {}
      if result_metadata["result_id"]
        identifier!(result_metadata["result_id"], "result_id")
        raise Invalid, "duplicate result_id" unless result_ids.add?(result_metadata["result_id"])
      end
      trace_id!(result_metadata["trace_id"]) if result_metadata["trace_id"]
      judge_trace_ids!(result_metadata["judge_trace_ids"])
    end
  end

  def object!(value, name)
    raise Invalid, "#{name} must be an object" unless value.is_a?(Hash)
  end

  def optional_object!(value, name)
    object!(value, name) unless value.nil?
  end

  def string!(value, name, max, required: false)
    return if value.nil? && !required
    raise Invalid, "#{name} must be a string of at most #{max} characters" unless value.is_a?(String) && value.length <= max
    raise Invalid, "#{name} is required" if required && value.strip.empty?
  end

  def identifier!(value, name)
    raise Invalid, "invalid #{name}" unless value.is_a?(String) && ID_PATTERN.match?(value)
  end

  def trace_id!(value)
    raise Invalid, "invalid trace ID" unless value.is_a?(String) && TRACE_PATTERN.match?(value)
  end

  def judge_trace_ids!(value)
    return if value.nil?
    raise Invalid, "judge_trace_ids must be an array of at most 100 IDs" unless value.is_a?(Array) && value.size <= 100

    value.each { |trace| trace_id!(trace) }
  end

  def numeric!(value, name, max: 1e15)
    return if value.nil?
    raise Invalid, "#{name} must be a finite number between 0 and #{max}" unless value.is_a?(Numeric) && value.finite? && value.between?(0, max)
  end

  def validate_json!(value, depth = 0)
    raise Invalid, "payload exceeds maximum nesting depth" if depth > 20

    case value
    when Hash
      value.each do |key, child|
        string!(key, "object key", 200, required: true)
        validate_json!(child, depth + 1)
      end
    when Array then value.each { |child| validate_json!(child, depth + 1) }
    when String then string!(value, "text", 100_000)
    when Numeric then raise Invalid, "non-finite number" unless value.finite?
    when NilClass, TrueClass, FalseClass then nil
    else raise Invalid, "unsupported JSON value"
    end
  end

  def canonical(value)
    case value
    when Hash then value.keys.sort.to_h { |key| [ key, canonical(value[key]) ] }
    when Array then value.map { |child| canonical(child) }
    else value
    end
  end
end
