# frozen_string_literal: true

require "test_helper"

class PlaywrightServiceTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @agent = create_agent(user: @user)
    @sandbox = SandboxSession.create!(
      session_id: SecureRandom.uuid,
      sandbox_type: "playwright_mcp",
      status: :ready,
      timeout_seconds: 300,
      max_runs: 10,
      expires_at: 1.hour.from_now
    )
    @service = PlaywrightService.new(sandbox_session: @sandbox)
  end

  test "initializes with sandbox session" do
    assert_equal @sandbox, @service.sandbox_session
    assert_nil @service.recording
  end

  test "start_recording creates a session recording" do
    recording = @service.start_recording

    assert recording.is_a?(SessionRecording)
    assert recording.persisted?
    assert_equal @sandbox, recording.sandbox_session
    assert @service.recording_middleware.present?
  end

  test "execute rejects unsupported actions" do
    result = @service.execute(action: "delete_everything", params: {})

    assert_not result[:success]
    assert_includes result[:error], "Unsupported action"
  end

  test "execute handles navigate action" do
    result = @service.execute(action: "navigate", params: { url: "https://example.com" })

    assert result[:success]
    assert_equal "navigate", result[:action]
  end

  test "execute handles click action" do
    result = @service.execute(action: "click", params: { selector: "button.submit" })

    assert result[:success]
    assert_equal "click", result[:action]
  end

  test "execute handles type action" do
    result = @service.execute(action: "type", params: { selector: "input.name", text: "Alice" })

    assert result[:success]
    assert_equal "type", result[:action]
  end

  test "execute handles screenshot action" do
    result = @service.execute(action: "screenshot", params: {})

    assert result[:success]
    assert_equal "screenshot", result[:action]
  end

  test "convenience methods work" do
    assert @service.navigate("https://example.com")[:success]
    assert @service.click("button")[:success]
    assert @service.type_text("input", "hello")[:success]
    assert @service.screenshot[:success]
  end

  test "action_log tracks executed actions" do
    @service.execute(action: "navigate", params: { url: "https://example.com" })
    @service.execute(action: "click", params: { selector: "button" })

    assert_equal 2, @service.action_log.size
    assert_equal "navigate", @service.action_log[0][:action]
    assert_equal "click", @service.action_log[1][:action]
  end

  test "complete returns summary" do
    @service.execute(action: "navigate", params: { url: "https://example.com" })
    @service.execute(action: "click", params: { selector: "a" })

    result = @service.complete!
    assert_equal 2, result[:actions_recorded]
  end

  test "all supported actions are mapped to MCP tools" do
    PlaywrightService::SUPPORTED_ACTIONS.each do |action|
      assert PlaywrightService::ACTION_TO_MCP_TOOL.key?(action),
        "Action '#{action}' should be mapped to an MCP tool"
    end
  end
end
