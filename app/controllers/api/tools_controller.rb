# frozen_string_literal: true

module Api
  class ToolsController < BaseController
    # GET /api/tools
    # Returns metadata for all available tools (for the agent builder UI)
    def index
      render json: {
        tools: ToolRegistry.tool_metadata,
        total: ToolRegistry::TOOLS.size
      }
    end

    # GET /api/tools/:id
    # Returns detailed definition for a specific tool
    def show
      tool_class = ToolRegistry.resolve(params[:id])

      if tool_class
        render json: {
          tool: tool_class.to_tool_definition.merge(
            display_name: params[:id].titleize,
            registered_name: params[:id]
          )
        }
      else
        render json: { error: "Tool not found: #{params[:id]}" }, status: :not_found
      end
    end

    # POST /api/tools/:id/test
    # Execute a tool with test parameters (for development/debugging)
    def test
      tool_class = ToolRegistry.resolve(params[:id])

      unless tool_class
        return render json: { error: "Tool not found: #{params[:id]}" }, status: :not_found
      end

      tool_params = params.fetch(:params, {}).to_unsafe_h.deep_symbolize_keys

      begin
        result = tool_class.call(**tool_params)
        render json: { result: result, tool: params[:id], success: true }
      rescue BaseTool::ParameterError => e
        render json: { error: e.message, type: "parameter_error", success: false }, status: :unprocessable_entity
      rescue BaseTool::ExecutionError => e
        render json: { error: e.message, type: "execution_error", success: false }, status: :unprocessable_entity
      rescue BaseTool::ToolError => e
        render json: { error: e.message, type: "tool_error", success: false }, status: :internal_server_error
      end
    end
  end
end
