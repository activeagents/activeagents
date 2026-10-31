module ProductSearch
  module Backends
    # Brave Search's web results (https://brave.com/search/api/): good for
    # marketplaces Google Shopping does not index (Grailed, Vinted, Reverb,
    # Discogs). Prices are parsed out of snippets, so they are a hint, not a
    # fact; the agent is told to inspect before it records. Set
    # BRAVE_SEARCH_API_KEY.
    class Brave < Backend
      ENDPOINT = URI("https://api.search.brave.com/res/v1/web/search")

      def initialize(api_key: ENV["BRAVE_SEARCH_API_KEY"])
        @api_key = api_key
      end

      def search(query, max_price_cents: nil, limit: 10)
        raise Error, "BRAVE_SEARCH_API_KEY is not set" if @api_key.blank?

        uri = ENDPOINT.dup
        uri.query = URI.encode_www_form(q: query, count: limit, safesearch: "off", text_decorations: false)
        body = get_json(uri, headers: { "X-Subscription-Token" => @api_key })
        results = Array(body.dig("web", "results"))

        results.filter_map { |row| build(row) }
               .select { |listing| within_budget?(listing, max_price_cents) }
               .first(limit)
      end

      private

      def build(row)
        return nil if row["url"].blank? || row["title"].blank?

        cents, currency = PriceParser.parse("#{row['title']} #{row['description']}")
        Listing.new(
          title: row["title"],
          url: row["url"],
          source: PriceParser.source_from_url(row["url"]),
          price_cents: cents,
          currency: currency,
          image_url: row.dig("thumbnail", "src").presence,
          description: row["description"].presence,
          listed_at: row["page_age"].presence
        )
      end
    end
  end
end
