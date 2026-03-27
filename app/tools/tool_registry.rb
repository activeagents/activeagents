# frozen_string_literal: true

# ToolRegistry - Central registry for discovering and resolving agent tools
#
# Maps tool name strings (as stored on Agent#tools) to their implementing classes.
# Used by the agent execution pipeline to resolve which tools an agent can invoke.
#
# Usage:
#   ToolRegistry.resolve("fetch")          # => FetchTool
#   ToolRegistry.definitions_for(["fetch", "bash"])  # => [{ name: "fetch", ... }, ...]
#   ToolRegistry.available_tools           # => { "fetch" => FetchTool, ... }
#
class ToolRegistry
  TOOLS = {
    "fetch"      => "FetchTool",
    "filesystem" => "FilesystemTool",
    "bash"       => "BashTool",
    "agents"     => "AgentsTool",
    "views"      => "ViewsTool",
    "prompts"    => "PromptsTool"
  }.freeze

  class << self
    # Resolve a tool name to its class
    def resolve(name)
      class_name = TOOLS[name.to_s]
      return nil unless class_name

      class_name.constantize
    end

    # Resolve multiple tool names, skipping unknown ones
    def resolve_all(names)
      Array(names).filter_map { |name| resolve(name) }
    end

    # Get tool definitions for a list of tool names (for LLM function calling)
    def definitions_for(names)
      resolve_all(names).map(&:to_tool_definition)
    end

    # Get all registered tools
    def available_tools
      TOOLS.transform_values { |class_name| class_name.constantize }
    end

    # Get metadata for all tools (for the agent builder UI)
    def tool_metadata
      TOOLS.map do |name, class_name|
        klass = class_name.constantize
        {
          name: name,
          display_name: name.titleize,
          description: klass.description,
          parameters: klass.to_tool_definition[:parameters]
        }
      end
    end

    # Execute a tool by name with given parameters
    def execute(name, **params)
      tool_class = resolve(name)
      raise BaseTool::ToolError, "Unknown tool: #{name}" unless tool_class

      tool_class.call(**params)
    end
  end
end
