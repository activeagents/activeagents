require "net/http"

module ProductSearch
  # What every search backend implements, plus the HTTP plumbing the live
  # ones share. Timeouts are short: a search is one tool call inside an
  # agent's turn, and a slow marketplace should fail the call, not the run.
  class Backend
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 12

    def name
      self.class.name.demodulize.underscore
    end

    # @return [Array<Listing>]
    def search(query, max_price_cents: nil, limit: 10)
      raise NotImplementedError, "#{self.class} must implement #search"
    end

    # Full details for one listing, when the backend can get them.
    # @return [Listing, nil]
    def fetch(url)
      nil
    end

    protected

    def get_json(uri, headers: {})
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      headers.each { |key, value| request[key] = value }

      response = http.request(request)
      raise Error, "#{name} search failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError, SocketError, Timeout::Error, SystemCallError, OpenSSL::SSL::SSLError => e
      raise Error, "#{name} search failed: #{e.message}"
    end

    def within_budget?(listing, max_price_cents)
      max_price_cents.nil? || listing.price_cents.nil? || listing.price_cents <= max_price_cents
    end
  end
end
