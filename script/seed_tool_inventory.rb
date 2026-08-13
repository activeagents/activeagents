# frozen_string_literal: true

# Seeds a realistic tool/MCP inventory for the demo account so the mounted
# dashboard's Tools and MCP Services views have something to render in
# development.
#
#   bin/rails runner script/seed_tool_inventory.rb
#
# Writes the same records a real run produces — telemetry traces with an
# offered tool roster and executed tool spans, plus solid_agent contexts,
# generations and tool messages — so the views exercise every detection
# path rather than reading from a fixture the app doesn't otherwise use.

user = User.find_by(email_address: "demo@example.com") || User.first
abort "No user to seed against" unless user

account = user.primary_account
abort "No account for #{user.email_address}" unless account

agent = user.agents.first
puts "Seeding tool inventory for #{account.name} (#{user.email_address})"

DECLARED = [
  { "name" => "mcp__playwright__browser_navigate", "description" => "Open a URL in the managed browser.", "parameters" => [ "url" ] },
  { "name" => "mcp__playwright__browser_snapshot", "description" => "Accessibility snapshot of the current page.", "parameters" => [] },
  { "name" => "mcp__playwright__browser_click", "description" => "Click an element from the latest snapshot.", "parameters" => [ "ref", "element" ] },
  { "name" => "mcp__github__create_issue", "description" => "File an issue on a GitHub repository.", "parameters" => [ "owner", "repo", "title", "body" ] },
  { "name" => "mcp__github__search_code", "description" => "Search code across repositories.", "parameters" => [ "query" ] },
  { "name" => "mcp__filesystem__read_text_file", "description" => "Read a UTF-8 file from an allowed directory.", "parameters" => [ "path" ] },
  { "name" => "web_search", "description" => "Search the web and return a short summary.", "parameters" => [ "query" ] },
  { "name" => "lookup_order", "description" => "Look up an order by its reference.", "parameters" => [ "order_id" ] },
  { "name" => "escalate_to_human", "description" => "Hand the conversation to a human agent.", "parameters" => [ "reason" ] }
].freeze

# name => [call count, error count, avg duration]
TRAFFIC = {
  "mcp__playwright__browser_navigate" => [ 24, 1, 380.0 ],
  "mcp__playwright__browser_snapshot" => [ 19, 0, 145.0 ],
  "mcp__playwright__browser_click" => [ 12, 2, 210.0 ],
  "mcp__github__create_issue" => [ 6, 0, 640.0 ],
  "mcp__github__search_code" => [ 9, 1, 520.0 ],
  "mcp__filesystem__read_text_file" => [ 31, 0, 22.0 ],
  "web_search" => [ 14, 0, 810.0 ],
  "lookup_order" => [ 7, 3, 95.0 ]
  # escalate_to_human is deliberately absent: offered every run, never called.
}.freeze

def build_trace(account:, agent_class:, calls:, timestamp:, declared: nil)
  spans = [
    {
      "span_id" => "r1", "parent_span_id" => nil, "name" => "#{agent_class}.respond",
      "type" => "root", "duration_ms" => 1400.0, "status" => "OK",
      "attributes" => { "agent.class" => agent_class, "agent.action" => "respond" },
      "tokens" => { "input" => 820, "output" => 240, "thinking" => 0 }
    }
  ]

  if declared
    spans << {
      "span_id" => "p1", "parent_span_id" => "r1", "name" => "prompt",
      "type" => "prompt", "duration_ms" => 4.0, "status" => "OK",
      "attributes" => { "prompt.input.tools" => declared.to_json }
    }
  end

  spans << {
    "span_id" => "l1", "parent_span_id" => "r1", "name" => "chat",
    "type" => "llm", "duration_ms" => 1200.0, "status" => "OK",
    "attributes" => { "llm.provider" => "anthropic", "llm.model" => "claude-sonnet-5" },
    "tokens" => { "input" => 820, "output" => 240, "thinking" => 0 }
  }

  calls.each_with_index do |call, index|
    attributes = { "tool.name" => call[:name] }
    attributes["tool.input.args"] = call[:args] if call[:args]
    attributes["error.message"] = call[:error] if call[:error]
    spans << {
      "span_id" => "t#{index}", "parent_span_id" => "l1", "name" => "tool.#{call[:name]}",
      "type" => "tool", "duration_ms" => call[:duration], "status" => call[:error] ? "ERROR" : "OK",
      "attributes" => attributes
    }
  end

  TelemetryTrace.create_from_payload(
    {
      "trace_id" => SecureRandom.hex(16),
      "service_name" => "support-app",
      "environment" => "production",
      "timestamp" => timestamp.iso8601(6),
      "spans" => spans
    },
    { "name" => "activeagent", "version" => "1.1.0" },
    account: account
  )
end

SAMPLE_ARGS = {
  "mcp__playwright__browser_navigate" => '{"url":"https://docs.activeagents.ai/tools"}',
  "mcp__github__create_issue" => '{"owner":"activeagents","repo":"activeagent","title":"Tool timeout"}',
  "mcp__filesystem__read_text_file" => '{"path":"/workspace/README.md"}',
  "web_search" => '{"query":"model context protocol servers"}',
  "lookup_order" => '{"order_id":"ORD-4417"}'
}.freeze

# Spread the traffic over the last few days so the window selectors differ.
pending = TRAFFIC.transform_values { |(count, errors, duration)| { remaining: count, errors: errors, duration: duration } }
trace_count = 0

24.times do |index|
  timestamp = (index * 5).hours.ago
  calls = pending.filter_map do |name, state|
    next if state[:remaining].zero?
    # Roughly two calls per tool per trace, front-loaded toward recent time.
    take = [ state[:remaining], 2 ].min
    state[:remaining] -= take

    Array.new(take) do
      error = if state[:errors].positive?
        state[:errors] -= 1
        "#{name.split('__').last} timed out after 30s"
      end
      { name: name, duration: state[:duration], args: SAMPLE_ARGS[name], error: error }
    end
  end.flatten

  next if calls.empty? && index.positive?

  build_trace(
    account: account,
    agent_class: index.even? ? "SupportAgent" : "ResearchAgent",
    calls: calls,
    timestamp: timestamp,
    declared: DECLARED
  )
  trace_count += 1
end

# solid_agent side: a context whose generations carry the offered roster in
# provenance and the tool calls the model made, plus the tool results.
context = AgentContext.create!(
  agent_name: "SupportAgent",
  action_name: "respond",
  contextable: agent,
  instructions: "You are a support agent."
)
context.add_user_message("Where is my order ORD-4417?")
context.generations.create!(
  model: "claude-sonnet-5",
  provider: "anthropic",
  finish_reason: "tool_calls",
  input_tokens: 820,
  output_tokens: 240,
  duration_seconds: 1.4,
  tool_calls: [
    { "name" => "lookup_order", "arguments" => { "order_id" => "ORD-4417" } },
    { "name" => "mcp__github__create_issue", "arguments" => { "title" => "Order lookup flaky" } }
  ],
  provenance: {
    "agent_class" => "SupportAgent",
    "tools" => DECLARED + [
      { "name" => "refund_order", "description" => "Issue a refund for an order.", "parameters" => [ "order_id", "amount" ] }
    ]
  }
)
context.add_tool_message(tool_call_id: SecureRandom.hex(4), tool_name: "lookup_order", result: "Shipped 2 days ago", arguments: { "order_id" => "ORD-4417" })
context.add_tool_message(tool_call_id: SecureRandom.hex(4), tool_name: "mcp__github__create_issue", result: "opened #412", arguments: { "title" => "Order lookup flaky" })

# One agent declares MCP servers it has not called yet, so the "configured"
# status has a representative in the view.
agent&.update!(mcp_servers: [ "filesystem", "sequential-thinking" ], tools: Array(agent.tools) | [ "search", "memory" ])

inventory = ActionAgent::ToolDiscovery.new(
  traces: TelemetryTrace.for_account(account),
  agents: ActionAgent.agents_for(account),
  hours: 24 * 7
).inventory
puts "  traces:  #{trace_count}"
puts "  tools:   #{inventory[:tools].size} (#{inventory[:summary][:active_tools]} active, #{inventory[:summary][:unused_tools]} unused)"
puts "  servers: #{inventory[:servers].count { |s| s[:status] == 'active' }} active / #{inventory[:servers].size} listed"
puts "  calls:   #{inventory[:summary][:total_calls]}"
