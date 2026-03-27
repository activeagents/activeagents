# frozen_string_literal: true

# FetchTool - HTTP fetching with optional content extraction
#
# Fetches content from URLs and optionally extracts specific elements
# using CSS selectors. Supports text, markdown, and JSON output formats.
#
# Usage:
#   FetchTool.call(url: "https://example.com")
#   FetchTool.call(url: "https://example.com", selector: "article", format: "markdown")
#
class FetchTool < BaseTool
  tool_name "fetch"
  description "Fetch content from a URL. Optionally extract specific elements with a CSS selector and convert to different formats."

  parameter :url, type: "string", description: "The URL to fetch content from", required: true
  parameter :selector, type: "string", description: "CSS selector to extract specific content (e.g. 'article', '.main-content', 'h1')"
  parameter :format, type: "string", description: "Output format", enum: %w[text markdown json], default: "text"
  parameter :headers, type: "object", description: "Additional HTTP headers to send with the request"

  MAX_CONTENT_LENGTH = 100_000 # ~100KB text limit to avoid token explosion
  REQUEST_TIMEOUT = 30 # seconds

  def call(url:, selector: nil, format: "text", headers: {})
    validate_url!(url)

    content = fetch_url(url, headers)
    content = extract_with_selector(content, selector) if selector.present?
    content = convert_format(content, format)
    content = truncate_content(content)

    {
      url: url,
      content: content,
      format: format,
      truncated: content.length >= MAX_CONTENT_LENGTH,
      fetched_at: Time.current.iso8601
    }
  rescue Net::TimeoutError, Net::OpenTimeout
    raise ExecutionError, "Request timed out after #{REQUEST_TIMEOUT}s for URL: #{url}"
  rescue SocketError, Errno::ECONNREFUSED => e
    raise ExecutionError, "Connection failed for URL: #{url} (#{e.message})"
  rescue URI::InvalidURIError
    raise ParameterError, "Invalid URL: #{url}"
  end

  private

  def validate_url!(url)
    uri = URI.parse(url)
    unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      raise ParameterError, "URL must use http or https scheme: #{url}"
    end

    # Block private/internal IPs to prevent SSRF
    if private_ip?(uri.host)
      raise ParameterError, "Fetching from private/internal addresses is not allowed"
    end
  end

  def fetch_url(url, headers)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = REQUEST_TIMEOUT
    http.read_timeout = REQUEST_TIMEOUT

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "ActiveAgents/1.0"
    request["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

    headers.each { |key, value| request[key.to_s] = value.to_s }

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      response.body.to_s.force_encoding("UTF-8")
    when Net::HTTPRedirection
      # Follow one redirect
      redirect_url = response["location"]
      fetch_url(redirect_url, headers)
    else
      raise ExecutionError, "HTTP #{response.code}: #{response.message} for URL: #{url}"
    end
  end

  def extract_with_selector(html, selector)
    # Use Nokogiri if available, otherwise return raw content
    if defined?(Nokogiri)
      doc = Nokogiri::HTML(html)
      elements = doc.css(selector)
      elements.map(&:text).join("\n\n")
    else
      # Basic extraction without Nokogiri - strip HTML tags
      strip_html_tags(html)
    end
  end

  def convert_format(content, format)
    case format
    when "markdown"
      html_to_markdown(content)
    when "json"
      begin
        JSON.parse(content)
        content # Already valid JSON
      rescue JSON::ParserError
        { text: content }.to_json
      end
    else
      strip_html_tags(content)
    end
  end

  def strip_html_tags(html)
    # Remove script and style tags entirely
    text = html.gsub(%r{<(script|style)[^>]*>.*?</\1>}mi, "")
    # Remove HTML tags
    text = text.gsub(/<[^>]+>/, " ")
    # Clean up whitespace
    text.gsub(/\s+/, " ").strip
  end

  def html_to_markdown(content)
    # Basic HTML to markdown conversion
    text = content.dup
    text.gsub!(%r{<h([1-6])[^>]*>(.*?)</h\1>}i) { |_| "#{"#" * Regexp.last_match(1).to_i} #{Regexp.last_match(2).strip}\n\n" }
    text.gsub!(%r{<p[^>]*>(.*?)</p>}mi) { |_| "#{Regexp.last_match(1).strip}\n\n" }
    text.gsub!(%r{<a[^>]*href="([^"]*)"[^>]*>(.*?)</a>}i) { |_| "[#{Regexp.last_match(2)}](#{Regexp.last_match(1)})" }
    text.gsub!(%r{<strong>(.*?)</strong>}i) { |_| "**#{Regexp.last_match(1)}**" }
    text.gsub!(%r{<em>(.*?)</em>}i) { |_| "*#{Regexp.last_match(1)}*" }
    text.gsub!(%r{<code>(.*?)</code>}i) { |_| "`#{Regexp.last_match(1)}`" }
    text.gsub!(%r{<li[^>]*>(.*?)</li>}i) { |_| "- #{Regexp.last_match(1).strip}\n" }
    text.gsub!(%r{<br\s*/?>}i, "\n")
    strip_html_tags(text)
  end

  def truncate_content(content)
    content.truncate(MAX_CONTENT_LENGTH)
  end

  def private_ip?(host)
    return false unless host

    begin
      addr = IPAddr.new(host)
      addr.private? || addr.loopback? || addr.link_local?
    rescue IPAddr::InvalidAddressError
      # Hostname, not IP - check for localhost
      host == "localhost" || host.end_with?(".local")
    end
  end
end
