require "test_helper"

class HunterAgentTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @hunt = create_hunt(@user)
    @run = @hunt.discovery_runs.create!(user: @user, fee_cents: 199)
  end

  test "offers its tools and its delegations to the model" do
    agent = HunterAgent.new
    agent.process(:hunt, run: @run, candidates: [])

    assert_equal %w[search_products inspect_listing record_finding], agent.prompt_options[:tools].map { |tool| tool[:name] }
    assert_equal 12, agent.prompt_options[:max_tool_turns]
    assert_equal @run.trace_id || agent.prompt_options[:trace_id], agent.prompt_options[:trace_id]

    delegated = HunterAgent.delegated_tools.map { |tool| tool[:name] || tool["name"] }
    assert_equal %w[evaluate_listing plan_queries], delegated.sort
  end

  test "search_products searches the backend and remembers what it saw" do
    agent = HunterAgent.new
    agent.process(:hunt, run: @run, candidates: [])

    result = agent.search_products(query: "Patagonia Synchilla Snap-T", limit: 3)

    assert_equal 3, result[:count]
    assert result[:results].all? { |listing| listing[:url].present? && listing[:price].present? }
    assert_equal "M", result[:results].first[:size]

    inspected = agent.inspect_listing(url: result[:results].first[:url])
    assert_equal result[:results].first[:title], inspected.dig(:listing, :title)
    assert inspected.dig(:listing, :description).present?

    assert_match "No listing found", agent.inspect_listing(url: "https://listings.example.com/nowhere")[:error]
  end

  test "search_products answers a backend failure as data the model can act on" do
    ProductSearch.backend = Class.new(ProductSearch::Backend) {
      def search(*) = raise(ProductSearch::Error, "HTTP 429")
    }.new

    result = HunterAgent.new.search_products(query: "anything")

    assert_equal 0, result[:count]
    assert_match "HTTP 429", result[:error]
  ensure
    ProductSearch.reset!
  end

  test "record_finding writes one finding per URL and fills in what the search saw" do
    agent = HunterAgent.new
    agent.process(:hunt, run: @run, candidates: [])
    url = agent.search_products(query: "Patagonia Synchilla Snap-T 90s USA")[:results].first[:url]

    first = agent.record_finding(url: url, title: "Snap-T, 90s, M", match_score: 92, verdict: "grail", rationale: "The one.", red_flags: [])
    assert first[:recorded]
    assert first[:created]

    finding = Finding.find(first[:finding_id])
    assert_equal 12_800, finding.price_cents
    assert_equal "grailed", finding.source
    assert_equal "M", finding.size
    assert_equal "agent", finding.scored_by
    assert_equal @run, finding.discovery_run

    again = agent.record_finding(url: url, title: "Snap-T", match_score: 50, verdict: "maybe", rationale: "Again.")
    assert again[:already_recorded]
    assert_equal 1, @hunt.findings.count
    assert_equal 92, finding.reload.match_score

    bad = agent.record_finding(url: "not a url", title: "x", match_score: 10, verdict: "pass", rationale: "x")
    assert_not bad[:recorded]
    assert_match "web address", bad[:error]
  end

  test "an agent judgement replaces a heuristic one for the same listing" do
    listing = ProductSearch.search("Patagonia Synchilla Snap-T 90s USA").first
    Discovery::FindingRecorder.record(@run, listing.to_h.merge(match_score: 70, verdict: "strong", rationale: "Heuristic"), scored_by: "heuristic")

    agent = HunterAgent.new
    agent.process(:hunt, run: @run, candidates: [ listing ])
    result = agent.record_finding(url: listing.url, title: listing.title, match_score: 95, verdict: "grail", rationale: "Seen it.")

    assert result[:already_recorded]
    finding = @hunt.findings.find_by!(url: listing.url)
    assert_equal 95, finding.match_score
    assert_equal "agent", finding.scored_by
  end

  test "a generation against the mock provider completes and is traced under the run's id" do
    ActionAgent::TelemetryTrace.delete_all

    response = HunterAgent.with(run: @run, candidates: [], trace_id: "trace-for-test").hunt.generate_now

    assert response.message.content.present?
    ActiveAgent::Telemetry.flush
    assert ActionAgent::TelemetryTrace.exists?(trace_id: "trace-for-test")
  end
end
