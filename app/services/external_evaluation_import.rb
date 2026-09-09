# frozen_string_literal: true

require "digest"

# Imports completed reports, never executes the reporting application's agent.
# The account lock and unique index make concurrent retries converge on one run.
class ExternalEvaluationImport
  class Invalid < StandardError; end
  class Conflict < StandardError; end

  MAX_BYTES = 2.megabytes
  MAX_RESULTS = 1000
  ID_PATTERN = /\A[a-zA-Z0-9_.:\/-]{1,200}\z/
  TRACE_PATTERN = /\A[a-zA-Z0-9_-]{1,128}\z/

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
      existing = EvaluationRun.find_by(account: @account, external_run_id: @payload["run_id"])
      if existing
        raise Conflict, "run_id already exists with a different report" unless existing.report_digest == digest
        return [ existing, true ]
      end

      evaluation = find_evaluation
      run = evaluation.evaluation_runs.create!(
        account: @account, external_run_id: @payload["run_id"], report_digest: digest,
        external_report: @payload["report"], status: :complete, scores: {},
        samples_evaluated: results.size, samples_passed: results.count { |result| result["status"] == "passed" },
        completed_at: Time.current
      )
      evaluation.touch
      [ run, false ]
    end
  end

  private

  def results
    @payload.fetch("report").fetch("results")
  end

  def find_evaluation
    identity = @payload.values_at("source", "agent_name", "suite")
    context = (@payload.dig("report", "metadata") || {}).slice("scope", "environment", "publishing_domain", "role")
    identity << canonical(context)
    key = Digest::SHA256.hexdigest(JSON.generate(identity))
    existing = Evaluation.find_by(account: @account, external_key: key)
    return existing if existing

    # Separate source/account namespaces prevent two apps with the same agent
    # class, or two accounts owned by one user, from sharing imported results.
    agent_key = Digest::SHA256.hexdigest(JSON.generate([ @account.id, *identity.first(2) ]))
    agent = @account.owner.agents.find_or_create_by!(slug: "external-#{agent_key}") do |record|
      record.name = @payload["agent_name"]
      record.agent_class_name = @payload["agent_name"]
      record.provider = results.first["provider"]
      record.model = results.first["model"]
      record.status = :observed
      record.description = "Evaluation reports from #{@payload['source']}"
    end
    agent.evaluations.create!(
      account: @account, external_key: key, name: "#{@payload['suite']} [#{key.first(12)}]", judge_kind: "external",
      judge_model: @payload.dig("report", "judge"), criteria: [], sample_size: [ results.size, 100 ].min,
      config: { "source" => @payload["source"], "suite" => @payload["suite"], "context" => context }
    )
  end

  def validate!
    object!(@payload, "payload")
    raise Invalid, "payload exceeds #{MAX_BYTES} bytes" if JSON.generate(@payload).bytesize > MAX_BYTES
    validate_json!(@payload)
    raise Invalid, "version must be 1" unless @payload["version"] == 1
    %w[run_id source suite].each { |key| identifier!(@payload[key], key) }
    string!(@payload["agent_name"], "agent_name", 100, required: true)
    raise Invalid, "agent_name must contain at least two characters" if @payload["agent_name"].length < 2
    report = @payload["report"]
    object!(report, "report")
    optional_object!(report["metadata"], "report.metadata")
    judge_trace_ids!(report.dig("metadata", "judge_trace_ids"))
    string!(report["judge"], "report.judge", 200)
    object!(report["models"], "report.models")
    raise Invalid, "report.models must contain 1-50 models" unless report["models"].size.between?(1, 50)
    raise Invalid, "report.results must contain 1-#{MAX_RESULTS} results" unless report["results"].is_a?(Array) && results.size.between?(1, MAX_RESULTS)
    pairs = []
    result_ids = []
    results.each_with_index do |result, index|
      object!(result, "result #{index}")
      %w[scenario_key label provider model].each { |key| string!(result[key], "result.#{key}", 200, required: true) }
      raise Invalid, "result label is missing from report.models" unless report["models"].key?(result["label"])
      pair = result.values_at("scenario_key", "label")
      raise Invalid, "duplicate scenario/model result" if pairs.include?(pair)
      pairs << pair
      raise Invalid, "invalid result status" unless %w[passed failed errored].include?(result["status"])
      numeric!(result["score"], "result.score", max: 1)
      optional_object!(result["scores"], "result.scores")
      (result["scores"] || {}).each_value { |score| numeric!(score, "criterion score", max: 1) }
      %w[duration_ms cost input_tokens output_tokens].each { |key| numeric!(result[key], "result.#{key}") }
      %w[prompt answer error recommendation].each { |key| string!(result[key], "result.#{key}", 100_000) }
      %w[group fault].each { |key| string!(result[key], "result.#{key}", 200) }
      optional_object!(result["metadata"], "result.metadata")
      metadata = result["metadata"] || {}
      if metadata["result_id"]
        identifier!(metadata["result_id"], "result_id")
        raise Invalid, "duplicate result_id" if result_ids.include?(metadata["result_id"])
        result_ids << metadata["result_id"]
      end
      trace_id!(metadata["trace_id"]) if metadata["trace_id"]
      judge_trace_ids!(metadata["judge_trace_ids"])
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
