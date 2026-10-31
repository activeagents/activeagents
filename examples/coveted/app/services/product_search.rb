# The search tool the agents call: one interface over several backends.
#
#   ProductSearch.search("Patagonia Synchilla Snap-T 90s", max_price_cents: 15_000)
#   #=> [#<ProductSearch::Listing title=... url=... price_cents=...>, ...]
#
# The backend is picked from the environment: PRODUCT_SEARCH_BACKEND names
# one outright; otherwise SerpApi when SERPAPI_KEY is set, Brave Search when
# BRAVE_SEARCH_API_KEY is set, and the offline sample catalog when neither
# is. Every backend answers with the same Listing struct, so the agents and
# the ranker never know which one ran.
module ProductSearch
  class Error < StandardError; end

  BACKENDS = {
    "catalog" => "ProductSearch::Backends::Catalog",
    "serpapi" => "ProductSearch::Backends::SerpApi",
    "brave" => "ProductSearch::Backends::Brave"
  }.freeze

  class << self
    attr_writer :backend

    def backend
      @backend ||= build(backend_name)
    end

    def backend_name
      ENV["PRODUCT_SEARCH_BACKEND"].presence ||
        (ENV["SERPAPI_KEY"].present? && "serpapi") ||
        (ENV["BRAVE_SEARCH_API_KEY"].present? && "brave") ||
        "catalog"
    end

    def build(name)
      BACKENDS.fetch(name.to_s) { raise Error, "Unknown search backend #{name.inspect}; one of #{BACKENDS.keys.join(', ')}" }.constantize.new
    end

    def reset!
      @backend = nil
    end

    # @return [Array<Listing>]
    def search(query, max_price_cents: nil, limit: 10)
      backend.search(query.to_s.squish, max_price_cents: max_price_cents, limit: limit.to_i.clamp(1, 20))
    end

    # @return [Listing, nil]
    def fetch(url)
      backend.fetch(url.to_s.strip)
    end
  end
end
