# frozen_string_literal: true

require "resolv"

# Server-executable tools for platform generation runs, keyed by the tool
# names an Agent enables in the builder (Agent::AVAILABLE_TOOLS).
#
# AgentExecutionService exposes each supported tool to the provider as a
# function-calling schema and routes invocations here, so real runs produce
# tool-call roundtrips that show up as :tool spans in Traces, tool messages
# in Interactions, and tool counts in Metrics.
#
# Only tools with a safe server-side implementation are mapped; anything
# else an agent enables (terminal, playwright, ...) is ignored for platform
# execution.
class AgentToolbox
  FETCH_LIMIT_BYTES = 50_000
  FETCH_TIMEOUT_SECONDS = 5

  # agent tool name => function-calling tool definitions (common format).
  DEFINITIONS = {
    "fetch" => [
      {
        name: "fetch_url",
        description: "Fetch a public http(s) URL and return the beginning of its body as text. Use for reading web pages or APIs.",
        parameters: {
          type: "object",
          properties: {
            url: { type: "string", description: "Absolute http(s) URL to fetch" }
          },
          required: [ "url" ]
        }
      }
    ],
    "search" => [
      {
        name: "web_search",
        description: "Search the web (DuckDuckGo instant answers) and return a short summary with related topics.",
        parameters: {
          type: "object",
          properties: {
            query: { type: "string", description: "The search query" }
          },
          required: [ "query" ]
        }
      }
    ],
    "code" => [
      {
        name: "calculate",
        description: "Evaluate an arithmetic expression (+, -, *, /, %, parentheses) and return the numeric result.",
        parameters: {
          type: "object",
          properties: {
            expression: { type: "string", description: "Arithmetic expression, e.g. (2 + 3) * 4.5" }
          },
          required: [ "expression" ]
        }
      }
    ]
  }.freeze

  # Function name => implementation method, for routing tool calls.
  FUNCTIONS = {
    "fetch_url" => :fetch_url,
    "web_search" => :web_search,
    "calculate" => :calculate
  }.freeze

  class << self
    # Tool definitions for the subset of an agent's enabled tools that have
    # server-side implementations.
    def definitions_for(tool_names)
      Array(tool_names).flat_map { |name| DEFINITIONS[name.to_s] || [] }
    end

    def function?(name)
      FUNCTIONS.key?(name.to_s)
    end

    # Executes a tool call. Returns a result hash; errors are returned as
    # { error: ... } so the model can react instead of the run crashing.
    def call(name, **kwargs)
      return { error: "Unknown tool: #{name}" } unless function?(name)

      public_send(FUNCTIONS.fetch(name.to_s), **kwargs)
    rescue ArgumentError => e
      { error: "Invalid arguments for #{name}: #{e.message}" }
    rescue StandardError => e
      Rails.logger.warn("[AgentToolbox] #{name} failed: #{e.class} - #{e.message}")
      { error: "#{name} failed: #{e.message}" }
    end

    def fetch_url(url:)
      uri = URI.parse(url.to_s)
      return { error: "Only http(s) URLs are supported" } unless uri.is_a?(URI::HTTP)
      return { error: "URL host is not allowed" } unless public_host?(uri.host)

      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: FETCH_TIMEOUT_SECONDS,
        read_timeout: FETCH_TIMEOUT_SECONDS
      ) { |http| http.get(uri.request_uri.presence || "/", { "User-Agent" => "ActiveAgents-Toolbox/1.0" }) }

      body = response.body.to_s.byteslice(0, FETCH_LIMIT_BYTES).to_s.scrub
      {
        url: url,
        status: response.code.to_i,
        content_type: response["Content-Type"],
        body: body,
        truncated: response.body.to_s.bytesize > FETCH_LIMIT_BYTES
      }
    rescue URI::InvalidURIError
      { error: "Invalid URL" }
    end

    def web_search(query:)
      uri = URI("https://api.duckduckgo.com/?#{URI.encode_www_form(q: query.to_s, format: "json", no_html: 1, skip_disambig: 1)}")
      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: true, open_timeout: FETCH_TIMEOUT_SECONDS, read_timeout: FETCH_TIMEOUT_SECONDS
      ) { |http| http.get(uri.request_uri) }
      data = JSON.parse(response.body)

      {
        query: query,
        abstract: data["AbstractText"].presence,
        answer: data["Answer"].presence,
        heading: data["Heading"].presence,
        related_topics: Array(data["RelatedTopics"]).first(5).filter_map { |topic| topic["Text"] }
      }
    end

    def calculate(expression:)
      { expression: expression, result: Calculator.evaluate(expression.to_s) }
    rescue Calculator::Error => e
      { error: e.message }
    end

    private

    # SSRF guard for fetch_url: reject hosts that resolve to loopback,
    # private, or link-local addresses.
    def public_host?(host)
      return false if host.blank?

      addresses = Resolv.getaddresses(host)
      return false if addresses.empty?

      addresses.all? do |address|
        ip = IPAddr.new(address)
        !(ip.loopback? || ip.private? || ip.link_local?)
      end
    rescue IPAddr::InvalidAddressError, Resolv::ResolvError
      false
    end
  end

  # Minimal recursive-descent arithmetic evaluator (no eval).
  # Grammar: expr := term (('+'|'-') term)*; term := factor (('*'|'/'|'%') factor)*;
  # factor := '-'? (number | '(' expr ')')
  module Calculator
    class Error < StandardError; end

    module_function

    def evaluate(expression)
      tokens = tokenize(expression)
      result, rest = parse_expr(tokens)
      raise Error, "Unexpected input: #{rest.join(' ')}" unless rest.empty?

      result = result.to_f
      result % 1 == 0 ? result.to_i : result.round(10)
    end

    def tokenize(expression)
      tokens = expression.scan(%r{\d+(?:\.\d+)?|[-+*/%()]|\S})
      invalid = tokens.grep_v(%r{\A(?:\d+(?:\.\d+)?|[-+*/%()])\z})
      raise Error, "Unsupported characters: #{invalid.uniq.join(' ')}" if invalid.any?
      raise Error, "Empty expression" if tokens.empty?

      tokens
    end

    def parse_expr(tokens)
      value, tokens = parse_term(tokens)
      while tokens.first == "+" || tokens.first == "-"
        op = tokens.shift
        rhs, tokens = parse_term(tokens)
        value = op == "+" ? value + rhs : value - rhs
      end
      [ value, tokens ]
    end

    def parse_term(tokens)
      value, tokens = parse_factor(tokens)
      while [ "*", "/", "%" ].include?(tokens.first)
        op = tokens.shift
        rhs, tokens = parse_factor(tokens)
        raise Error, "Division by zero" if rhs.zero? && op != "*"
        value = case op
        when "*" then value * rhs
        when "/" then value / rhs
        else value % rhs
        end
      end
      [ value, tokens ]
    end

    def parse_factor(tokens)
      raise Error, "Unexpected end of expression" if tokens.empty?

      if tokens.first == "-"
        tokens.shift
        value, tokens = parse_factor(tokens)
        return [ -value, tokens ]
      end

      token = tokens.shift
      if token == "("
        value, tokens = parse_expr(tokens)
        raise Error, "Missing closing parenthesis" unless tokens.shift == ")"
        [ value, tokens ]
      elsif token =~ /\A\d/
        [ token.include?(".") ? token.to_f : Rational(token), tokens ]
      else
        raise Error, "Unexpected token: #{token}"
      end
    end
  end
end
