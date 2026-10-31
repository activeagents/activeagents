module ProductSearch
  module Backends
    # Google Shopping through SerpApi (https://serpapi.com): structured
    # listings with price, merchant and thumbnail. Set SERPAPI_KEY.
    class SerpApi < Backend
      ENDPOINT = URI("https://serpapi.com/search.json")

      def initialize(api_key: ENV["SERPAPI_KEY"])
        @api_key = api_key
      end

      def search(query, max_price_cents: nil, limit: 10)
        raise Error, "SERPAPI_KEY is not set" if @api_key.blank?

        uri = ENDPOINT.dup
        uri.query = URI.encode_www_form(engine: "google_shopping", q: query, num: limit, api_key: @api_key)
        results = Array(get_json(uri)["shopping_results"])

        results.filter_map { |row| build(row) }
               .select { |listing| within_budget?(listing, max_price_cents) }
               .first(limit)
      end

      private

      def build(row)
        url = row["product_link"].presence || row["link"].presence
        return nil if url.blank? || row["title"].blank?

        cents, currency =
          if row["extracted_price"]
            [ (row["extracted_price"].to_f * 100).round, PriceParser.parse(row["price"].to_s)&.last || "USD" ]
          else
            PriceParser.parse(row["price"].to_s)
          end

        Listing.new(
          title: row["title"],
          url: url,
          source: row["source"].to_s.downcase.presence || PriceParser.source_from_url(url),
          price_cents: cents,
          currency: currency,
          condition: row["second_hand_condition"].presence,
          image_url: row["thumbnail"].presence,
          description: [ row["snippet"], row["delivery"] ].compact_blank.join(". ").presence
        )
      end
    end
  end
end
