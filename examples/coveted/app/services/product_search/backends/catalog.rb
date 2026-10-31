module ProductSearch
  module Backends
    # The offline backend: config/catalog.yml, matched by keyword overlap.
    # Enough to run the whole product loop, and the test suite, without a
    # network. Swap in SerpApi or Brave for real marketplaces.
    class Catalog < Backend
      PATH = Rails.root.join("config/catalog.yml")
      STOPWORDS = %w[the a an of in for and with or to from on at by size].freeze

      def initialize(path: PATH)
        @path = path
      end

      def listings
        @listings ||= YAML.safe_load_file(@path, permitted_classes: [ Date ]).map { |row| build(row) }
      end

      # Attribution for a catalog picture, by its image URL: the sample pictures
      # are free-licensed photographs that ask to be credited.
      # @return [Hash, nil] credit (text) and source (page URL)
      def credit_for(image_url)
        listings # ensure built
        credits[image_url.to_s]
      end

      def self.credit_for(image_url)
        (@default ||= new).credit_for(image_url)
      end

      def search(query, max_price_cents: nil, limit: 10)
        terms = tokenize(query)
        return [] if terms.empty?

        listings
          .map { |listing| [ score(listing, terms), listing ] }
          .select { |score, listing| score.positive? && within_budget?(listing, max_price_cents) }
          .sort_by { |score, listing| [ -score, listing.title ] }
          .first(limit)
          .map(&:last)
      end

      def fetch(url)
        listings.find { |listing| listing.url == url }
      end

      private

      def build(row)
        row = row.with_indifferent_access
        Listing.new(
          title: row[:title],
          url: row[:url],
          source: row[:source],
          price_cents: row[:price] && (row[:price].to_f * 100).round,
          currency: row[:currency] || "USD",
          condition: row[:condition],
          size: row[:size]&.to_s,
          brand: row[:brand],
          image_url: row[:image_url],
          description: row[:description],
          listed_at: row[:listed_at]
        ).tap do |listing|
          searchable[listing.url] = tokenize([ listing.title, listing.brand, Array(row[:keywords]).join(" "), listing.description ].join(" "))
          credits[listing.image_url.to_s] = { credit: row[:image_credit], source: row[:image_source] } if row[:image_credit].present?
        end
      end

      def searchable
        @searchable ||= {}
      end

      def credits
        @credits ||= {}
      end

      def score(listing, terms)
        words = searchable[listing.url]
        overlap = terms & words
        return 0 if overlap.empty?

        # Multi-word matches count for more than a single shared word, so a
        # query for a specific model outranks everything from the same brand.
        overlap.size * 2 + (overlap.size == terms.size ? 3 : 0)
      end

      def tokenize(text)
        text.to_s.downcase.scan(/[a-z0-9][a-z0-9'\-]*/).map { |word| word.delete("'") }
            .reject { |word| word.size < 2 || STOPWORDS.include?(word) }.uniq
      end
    end
  end
end
