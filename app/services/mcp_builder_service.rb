# frozen_string_literal: true

# McpBuilderService - Build custom MCP servers from tool definitions
#
# Generates MCP server code from tool specifications, stores it, and
# returns the configuration needed to run the server. This enables agents
# to dynamically create and use custom MCP servers.
#
# Usage:
#   builder = McpBuilderService.new(agent: agent)
#   config = builder.build(
#     name: "my_tools",
#     tools: [
#       { name: "lookup_user", description: "Look up user by email", handler: "...", parameters: {...} }
#     ]
#   )
#   # config => { command: "node", args: ["path/to/server.js"], env: {} }
#
class McpBuilderService
  class BuildError < StandardError; end

  MCP_SERVER_TEMPLATE = <<~JS
    #!/usr/bin/env node
    import { Server } from '@modelcontextprotocol/sdk/server/index.js';
    import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
    import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';

    const server = new Server({
      name: '%{name}',
      version: '%{version}'
    }, {
      capabilities: { tools: {} }
    });

    // Tool definitions
    const TOOLS = %{tools_json};

    server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: TOOLS.map(t => ({
        name: t.name,
        description: t.description,
        inputSchema: t.parameters || { type: 'object', properties: {} }
      }))
    }));

    server.setRequestHandler(CallToolRequestSchema, async (request) => {
      const { name, arguments: args } = request.params;
      const tool = TOOLS.find(t => t.name === name);

      if (!tool) {
        throw new Error(`Unknown tool: ${name}`);
      }

      try {
        %{tool_handlers}
        return { content: [{ type: 'text', text: JSON.stringify({ error: 'No handler for tool: ' + name }) }] };
      } catch (error) {
        return { content: [{ type: 'text', text: JSON.stringify({ error: error.message }) }], isError: true };
      }
    });

    const transport = new StdioServerTransport();
    await server.connect(transport);
  JS

  attr_reader :agent

  def initialize(agent:)
    @agent = agent
  end

  # Build a custom MCP server from tool specifications
  def build(name:, tools:, version: "1.0.0")
    validate_tools!(tools)

    server_code = generate_server_code(
      name: name,
      version: version,
      tools: tools
    )

    storage_path = store_server(name, server_code)

    {
      name: name,
      command: "node",
      args: [ storage_path ],
      env: extract_required_env(tools),
      tools: tools.map { |t| t[:name] || t["name"] },
      storage_path: storage_path,
      version: version
    }
  end

  # Validate tool specifications
  def validate(tools:)
    errors = []

    tools.each_with_index do |tool, i|
      name = tool[:name] || tool["name"]
      errors << "Tool #{i}: missing name" if name.blank?
      errors << "Tool #{i}: missing description" if (tool[:description] || tool["description"]).blank?

      if name.present? && !name.match?(/\A[a-z][a-z0-9_]*\z/)
        errors << "Tool #{i}: name must be lowercase alphanumeric with underscores"
      end
    end

    { valid: errors.empty?, errors: errors }
  end

  # Generate a preview of the MCP server code without storing it
  def preview(name:, tools:, version: "1.0.0")
    validate_tools!(tools)
    generate_server_code(name: name, version: version, tools: tools)
  end

  private

  def validate_tools!(tools)
    result = validate(tools: tools)
    raise BuildError, result[:errors].join("; ") unless result[:valid]
  end

  def generate_server_code(name:, version:, tools:)
    tools_json = tools.map do |tool|
      {
        name: tool[:name] || tool["name"],
        description: tool[:description] || tool["description"],
        parameters: tool[:parameters] || tool["parameters"] || { type: "object", properties: {} }
      }
    end

    tool_handlers = generate_tool_handlers(tools)

    format(
      MCP_SERVER_TEMPLATE,
      name: escape_js(name),
      version: escape_js(version),
      tools_json: JSON.pretty_generate(tools_json),
      tool_handlers: tool_handlers
    )
  end

  def generate_tool_handlers(tools)
    handlers = tools.map do |tool|
      name = tool[:name] || tool["name"]
      handler = tool[:handler] || tool["handler"]

      if handler.present?
        <<~JS.strip
          if (name === '#{escape_js(name)}') {
            #{handler}
          }
        JS
      else
        <<~JS.strip
          if (name === '#{escape_js(name)}') {
            return { content: [{ type: 'text', text: JSON.stringify({ tool: '#{escape_js(name)}', args, message: 'Handler not implemented' }) }] };
          }
        JS
      end
    end

    handlers.join("\n      ")
  end

  def store_server(name, code)
    # Store in the app's tmp directory for local development
    # In production, this would use GCS or another storage service
    dir = Rails.root.join("tmp", "mcp_servers", agent.id.to_s, name.parameterize)
    FileUtils.mkdir_p(dir)

    path = dir.join("server.mjs")
    File.write(path, code)

    path.to_s
  end

  def extract_required_env(tools)
    env = {}
    tools.each do |tool|
      env_vars = tool[:env] || tool["env"] || {}
      env.merge!(env_vars)
    end
    env
  end

  def escape_js(str)
    str.to_s.gsub("'", "\\\\'").gsub("\n", "\\n")
  end
end
