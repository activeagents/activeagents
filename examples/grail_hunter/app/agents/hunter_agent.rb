# The agent that runs a hunt.
#
# It reads the collector's brief and a first batch of candidate listings,
# then works the marketplaces through its tools: search_products for more
# listings, inspect_listing for details, and record_finding for every
# listing worth showing. Scoring is delegated to ListingEvaluatorAgent and
# query planning to QueryPlannerAgent, each under a budget. The
# conversation, tool exchange included, persists through solid_agent on the
# run that started it. Discovery::Pipeline drives one run end to end.
class HunterAgent < ApplicationAgent
  include SolidAgent::HasContext

  has_context

  MAX_TOOL_TURNS = 12

  SEARCH_PRODUCTS_TOOL = {
    name: "search_products",
    description: "Search the marketplaces for listings matching a query. Use specific queries: brand, " \
                 "model, era, colourway, size, common abbreviations. Returns listings with price, " \
                 "marketplace, condition and size where the marketplace lists them.",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query, e.g. 'Patagonia Synchilla Snap-T 90s made in USA M'" },
        max_price: { type: "number", description: "Only return listings at or under this price, in the hunt's currency" },
        limit: { type: "integer", description: "Maximum listings to return (default 8, at most 20)" }
      },
      required: [ "query" ]
    }
  }.freeze

  INSPECT_LISTING_TOOL = {
    name: "inspect_listing",
    description: "Fetch the full details of one listing by URL: description, condition, size, price. " \
                 "Use it before recording a listing whose search snippet left something unclear.",
    parameters: {
      type: "object",
      properties: {
        url: { type: "string", description: "The listing URL exactly as a search result gave it" }
      },
      required: [ "url" ]
    }
  }.freeze

  RECORD_FINDING_TOOL = {
    name: "record_finding",
    description: "Record a listing worth the collector's attention. Only record listings that came " \
                 "back from search_products, and only after evaluating them. Score 0-100: 100 is " \
                 "exactly the item, right size, within budget.",
    parameters: {
      type: "object",
      properties: {
        url: { type: "string", description: "The listing URL exactly as the search result gave it" },
        title: { type: "string" },
        match_score: { type: "integer", description: "0-100" },
        verdict: { type: "string", enum: Finding::VERDICTS, description: "grail (90+), strong (70-89), maybe (40-69)" },
        rationale: { type: "string", description: "Two or three sentences for the collector: why this one, and what to check" },
        red_flags: { type: "array", items: { type: "string" }, description: "Anything that argues against it" },
        price: { type: "number" },
        currency: { type: "string", description: "ISO code, e.g. USD" },
        source: { type: "string", description: "Marketplace name" },
        condition: { type: "string" },
        size: { type: "string" },
        image_url: { type: "string" }
      },
      required: %w[url title match_score verdict rationale]
    }
  }.freeze

  TOOLS = [ SEARCH_PRODUCTS_TOOL, INSPECT_LISTING_TOOL, RECORD_FINDING_TOOL ].freeze

  # A sub-agent is a loop inside the loop: these cap what one hunt may spend.
  delegation_budget max_calls: 16, max_duration: 180
  delegate_to ListingEvaluatorAgent, budget: { max_calls: 12, timeout: 45 }
  delegate_to QueryPlannerAgent, budget: { max_calls: 2, timeout: 30 }

  # The one action. Its message is app/views/agents/hunter/hunt.md.erb, its
  # system prompt app/views/agents/hunter/instructions.md.erb.
  #
  # Keyword arguments default to params so both ways of running it work:
  #   HunterAgent.with(run:, candidates:).hunt.generate_now   (the pipeline)
  #   agent.process(:hunt, run:, candidates:)                 (a test, no model)
  def hunt(run: params[:run], candidates: params[:candidates], trace_id: params[:trace_id])
    @run = run
    @hunt = run.hunt
    @candidates = Array(candidates)
    @candidates.each { |listing| seen[listing.url] = listing }

    new_trace!(trace_id)
    load_context(contextable: @run)

    prompt(tools: TOOLS, max_tool_turns: MAX_TOOL_TURNS)
  end

  # ---- Tools. The model calls these by name; the framework routes them. ----

  def search_products(query:, max_price: nil, limit: 8)
    max_cents = max_price.present? ? (max_price.to_f * 100).round : @hunt&.max_price_cents
    listings = ProductSearch.search(query, max_price_cents: max_cents, limit: limit.to_i.clamp(1, 20))
    listings.each { |listing| seen[listing.url] = listing }

    { query: query, count: listings.size, results: listings.map(&:tool_payload) }
  rescue ProductSearch::Error => e
    { query: query, count: 0, results: [], error: e.message }
  end

  def inspect_listing(url:)
    listing = seen[url] || ProductSearch.fetch(url)
    return { error: "No listing found at #{url}. Only inspect URLs that came back from search_products." } unless listing

    seen[listing.url] = listing
    { listing: listing.tool_payload }
  end

  def record_finding(url:, title:, match_score:, verdict:, rationale:, red_flags: [], price: nil,
                     currency: nil, source: nil, condition: nil, size: nil, image_url: nil)
    return { recorded: false, error: "No run to record against" } unless @run

    listing = seen[url]
    attrs = {
      url: url,
      title: title,
      match_score: match_score.to_i.clamp(0, 100),
      verdict: verdict.to_s.presence_in(Finding::VERDICTS) || "maybe",
      rationale: rationale,
      red_flags: Array(red_flags).map(&:to_s),
      price_cents: price.present? ? (price.to_f * 100).round : listing&.price_cents,
      currency: currency.presence || listing&.currency,
      source: source.presence || listing&.source,
      condition: condition.presence || listing&.condition,
      size: size.presence || listing&.size,
      image_url: image_url.presence || listing&.image_url,
      description: listing&.description,
      listed_at: listing&.listed_at
    }

    finding, created = Discovery::FindingRecorder.record(@run, attrs, scored_by: "agent")
    { recorded: true, created: created, finding_id: finding.id, already_recorded: !created }
  rescue ActiveRecord::RecordInvalid => e
    { recorded: false, error: e.message }
  end

  private

  # Listings this run has seen, by URL, so record_finding can fill in what
  # the model leaves out and inspect_listing needs no second search.
  def seen
    @seen ||= {}
  end
end
