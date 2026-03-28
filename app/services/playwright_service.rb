# frozen_string_literal: true

# PlaywrightService - Browser automation via Playwright MCP
#
# Provides a high-level interface for browser automation within sandbox sessions.
# Wraps MCP tool calls with recording support, session management, and error handling.
#
# Usage:
#   service = PlaywrightService.new(sandbox_session: session)
#   service.start_recording
#   service.execute(action: "navigate", params: { url: "https://example.com" })
#   service.execute(action: "click", params: { selector: "button.submit" })
#   result = service.execute(action: "screenshot")
#   service.complete!
#
class PlaywrightService
  class PlaywrightError < StandardError; end

  SUPPORTED_ACTIONS = %w[
    navigate click type screenshot evaluate
    hover select_option press_key fill_form
    wait_for drag file_upload handle_dialog
    snapshot close tabs resize
  ].freeze

  # Map our action names to Playwright MCP tool names
  ACTION_TO_MCP_TOOL = {
    "navigate" => "browser_navigate",
    "click" => "browser_click",
    "type" => "browser_type",
    "screenshot" => "browser_take_screenshot",
    "evaluate" => "browser_evaluate",
    "hover" => "browser_hover",
    "select_option" => "browser_select_option",
    "press_key" => "browser_press_key",
    "fill_form" => "browser_fill_form",
    "wait_for" => "browser_wait_for",
    "drag" => "browser_drag",
    "file_upload" => "browser_file_upload",
    "handle_dialog" => "browser_handle_dialog",
    "snapshot" => "browser_snapshot",
    "close" => "browser_close",
    "tabs" => "browser_tabs",
    "resize" => "browser_resize"
  }.freeze

  attr_reader :sandbox_session, :recording, :recording_middleware

  def initialize(sandbox_session:, agent_run: nil)
    @sandbox_session = sandbox_session
    @agent_run = agent_run
    @recording = nil
    @recording_middleware = nil
    @action_log = []
  end

  def start_recording(name: nil)
    @recording = SessionRecording.start!(
      sandbox_session: sandbox_session,
      agent_run: @agent_run,
      name: name || "Playwright session #{Time.current.strftime('%Y-%m-%d %H:%M')}"
    )

    @recording_middleware = MCPRecordingMiddleware.new(
      session_recording: @recording,
      sandbox_session: sandbox_session,
      agent_run: @agent_run
    )

    @recording
  end

  def execute(action:, params: {})
    action = action.to_s
    unless SUPPORTED_ACTIONS.include?(action)
      raise PlaywrightError, "Unsupported action: #{action}. Supported: #{SUPPORTED_ACTIONS.join(', ')}"
    end

    mcp_tool = ACTION_TO_MCP_TOOL[action]
    mcp_params = build_mcp_params(action, params)

    log_action(action, params)

    result = if @recording_middleware
      @recording_middleware.intercept(tool_name: mcp_tool, parameters: mcp_params) do
        call_mcp_tool(mcp_tool, mcp_params)
      end
    else
      call_mcp_tool(mcp_tool, mcp_params)
    end

    {
      action: action,
      success: true,
      result: result,
      screenshot: extract_screenshot(result)
    }
  rescue => e
    {
      action: action,
      success: false,
      error: e.message
    }
  end

  def navigate(url)
    execute(action: "navigate", params: { url: url })
  end

  def click(selector)
    execute(action: "click", params: { selector: selector })
  end

  def type_text(selector, text)
    execute(action: "type", params: { selector: selector, text: text })
  end

  def screenshot
    execute(action: "screenshot", params: {})
  end

  def evaluate(script)
    execute(action: "evaluate", params: { script: script })
  end

  def complete!
    @recording_middleware&.complete!
    { recording_id: @recording&.id, actions_recorded: @action_log.size }
  end

  def fail!(error_message = nil)
    @recording_middleware&.fail!(error_message)
  end

  def action_log
    @action_log.dup
  end

  private

  def call_mcp_tool(tool_name, params)
    # In production, this calls the actual MCP server
    # The MCP client is configured per-sandbox
    if sandbox_session.cloud_run_url.present?
      call_remote_mcp(tool_name, params)
    else
      call_local_mcp(tool_name, params)
    end
  end

  def call_remote_mcp(tool_name, params)
    require "net/http"

    uri = URI("#{sandbox_session.cloud_run_url}/mcp/tools/#{tool_name}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = params.to_json

    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    raise PlaywrightError, "MCP call failed: #{e.message}"
  end

  def call_local_mcp(tool_name, _params)
    # Local/development fallback - return mock result
    {
      "success" => true,
      "tool" => tool_name,
      "mock" => true,
      "message" => "Local MCP mock - configure cloud_run_url for real execution"
    }
  end

  def build_mcp_params(action, params)
    case action
    when "navigate"
      { "url" => params[:url] || params["url"] }
    when "click"
      { "ref" => params[:selector] || params["selector"] || params[:ref] || params["ref"] }
    when "type"
      {
        "ref" => params[:selector] || params["selector"] || params[:ref] || params["ref"],
        "text" => params[:text] || params["text"]
      }
    when "evaluate"
      { "function" => params[:script] || params["script"] || params[:function] || params["function"] }
    when "screenshot"
      { "fullPage" => params[:full_page] || false }
    when "fill_form"
      { "fields" => params[:fields] || params["fields"] || [] }
    when "wait_for"
      {
        "selector" => params[:selector] || params["selector"],
        "timeout" => params[:timeout] || 5000
      }
    when "resize"
      {
        "width" => params[:width] || params["width"] || 1280,
        "height" => params[:height] || params["height"] || 720
      }
    else
      params.transform_keys(&:to_s)
    end
  end

  def log_action(action, params)
    @action_log << {
      action: action,
      params: params,
      timestamp: Time.current.iso8601
    }
  end

  def extract_screenshot(result)
    return nil unless result.is_a?(Hash)

    result["screenshot"] || result[:screenshot] ||
      result.dig("data", "screenshot")
  end
end
