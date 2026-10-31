module Discovery
  # One discovery run, start to finish.
  #
  #   1. The search backend fetches candidates for the hunt's queries, minus
  #      listings the collector has already been shown.
  #   2. HunterAgent reads the brief and the candidates. Through its tools it
  #      searches further, inspects listings, scores them by delegating to
  #      ListingEvaluatorAgent, and records the keepers with record_finding.
  #   3. Candidates the agent never recorded get a heuristic score, so a
  #      provider that cannot call tools (the mock) still yields findings.
  #   4. The run is closed out: summary, tokens, trace id, the fee the plan
  #      sets, the hunt's next scheduled run, and a digest email.
  #
  # A failure marks the run failed with the error and does not raise: the
  # run stays visible on the hunt page, and the schedule moves on so one bad
  # run cannot stall a hunt.
  class Pipeline
    MAX_CANDIDATES = 12
    PER_QUERY = 8
    # Below this a heuristic match is noise rather than a find.
    MIN_HEURISTIC_SCORE = 40

    def self.call(run)
      new(run).call
    end

    def initialize(run)
      @run = run
      @hunt = run.hunt
      @search_errors = []
    end

    def call
      return @run if @run.finished?

      @run.update!(status: "running", started_at: Time.current, trace_id: @run.trace_id.presence || SecureRandom.uuid)

      candidates = gather_candidates
      response = HunterAgent.with(run: @run, candidates: candidates, trace_id: @run.trace_id).hunt.generate_now
      backfill_heuristics(candidates)
      close_out!(response)

      Billing.record_run_fee!(@run)
      @hunt.mark_ran!
      FindingsMailer.digest(@run).deliver_later if @run.new_findings_count.positive?
      @run
    rescue StandardError => e
      Rails.logger.error("[Discovery::Pipeline] run #{@run.id} failed: #{e.class}: #{e.message}")
      @run.update!(status: "failed", finished_at: Time.current, error_message: "#{e.class}: #{e.message}".truncate(1000))
      @hunt.mark_ran!
      @run
    end

    private

    def gather_candidates
      queries = @hunt.search_queries
      known = @hunt.known_urls.to_set
      seen = {}

      queries.each do |query|
        ProductSearch.search(query, max_price_cents: nil, limit: PER_QUERY).each do |listing|
          next if listing.url.blank? || known.include?(listing.url) || seen.key?(listing.url)

          seen[listing.url] = listing
        end
      rescue ProductSearch::Error => e
        @search_errors << "#{query}: #{e.message}"
      end

      @run.update!(queries: queries, candidate_count: seen.size)
      seen.values.first(MAX_CANDIDATES)
    end

    # Over-budget candidates are kept on purpose: the agent is told the
    # budget and decides whether a little over is still worth showing.
    def backfill_heuristics(candidates)
      ranker = HeuristicRanker.new(@hunt)
      recorded = @run.findings.pluck(:url).to_set

      candidates.each do |listing|
        next if recorded.include?(listing.url)

        scored = ranker.score(listing)
        next if scored[:match_score] < MIN_HEURISTIC_SCORE

        FindingRecorder.record(@run, listing.to_h.merge(scored), scored_by: "heuristic")
      end
    end

    def close_out!(response)
      summary = summary_from(response)
      usage = response.respond_to?(:usage) ? response.usage : nil
      scored_by = @run.findings.where(scored_by: "agent").exists? ? "agent" : "heuristic"

      @run.update!(
        status: "completed",
        finished_at: Time.current,
        summary: summary[:summary],
        confidence: summary[:confidence],
        provider: ApplicationAgent::PROVIDER.to_s,
        model: model_from(response),
        input_tokens: usage&.input_tokens.to_i,
        output_tokens: usage&.output_tokens.to_i,
        new_findings_count: @run.findings.count,
        scored_by: scored_by,
        error_message: @search_errors.presence&.join("\n")
      )
    end

    # The agent is asked to finish with a JSON summary. A provider that
    # ignores that (the mock answers in pig latin) still gets a summary: the
    # message itself, so the run page always shows what the model said.
    def summary_from(response)
      message = response.message
      json = message.respond_to?(:parsed_json) ? safe_parsed_json(message) : nil

      if json.is_a?(Hash) && json[:summary].present?
        { summary: json[:summary].to_s, confidence: json[:confidence].to_s.presence_in(%w[high medium low]) }
      else
        content = message&.content
        content = content.map { |block| block.is_a?(Hash) ? block[:text] : block.to_s }.join("\n") if content.is_a?(Array)
        { summary: content.to_s.squish.truncate(2000).presence || "The agent finished without a summary.", confidence: nil }
      end
    end

    def safe_parsed_json(message)
      message.parsed_json
    rescue StandardError
      nil
    end

    def model_from(response)
      raw = response.raw_response
      raw = raw.to_h if !raw.is_a?(Hash) && raw.respond_to?(:to_h)
      raw.is_a?(Hash) ? (raw["model"] || raw[:model]) : nil
    rescue StandardError
      nil
    end
  end
end
