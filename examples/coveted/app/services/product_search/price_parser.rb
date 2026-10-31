module ProductSearch
  # Pulls the first price out of free text: "$1,250.00", "€300", "45 GBP".
  module PriceParser
    SYMBOLS = { "$" => "USD", "€" => "EUR", "£" => "GBP", "¥" => "JPY" }.freeze
    CODES = %w[USD EUR GBP JPY CAD AUD].freeze

    SYMBOL_PATTERN = /(?<symbol>[$€£¥])\s?(?<amount>\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)/
    CODE_PATTERN = /(?<amount>\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)\s?(?<code>#{CODES.join('|')})\b/i
    LEADING_CODE_PATTERN = /\b(?<code>#{CODES.join('|')})\s?(?<amount>\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)/i

    module_function

    # @return [Array(Integer, String), nil] cents and ISO currency code
    def parse(text)
      text = text.to_s
      return nil if text.blank?

      if (match = text.match(SYMBOL_PATTERN))
        [ cents(match[:amount]), SYMBOLS.fetch(match[:symbol]) ]
      elsif (match = text.match(CODE_PATTERN) || text.match(LEADING_CODE_PATTERN))
        [ cents(match[:amount]), match[:code].upcase ]
      end
    end

    def cents(amount)
      (amount.to_s.delete(",").to_f * 100).round
    end

    # The domain's marketplace name: "www.grailed.com" -> "grailed".
    def source_from_url(url)
      host = URI.parse(url.to_s).host.to_s.downcase.delete_prefix("www.")
      host.split(".").first.presence
    rescue URI::InvalidURIError
      nil
    end
  end
end
