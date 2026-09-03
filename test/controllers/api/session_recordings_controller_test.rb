# frozen_string_literal: true

require "test_helper"

class Api::SessionRecordingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(email: "recording-owner-#{SecureRandom.hex(4)}@example.com")
    @owner_account = create_account(owner: @owner)

    @intruder = create_user(email: "recording-intruder-#{SecureRandom.hex(4)}@example.com")
    @intruder_account = create_account(owner: @intruder)

    @recording = SessionRecording.create!(
      name: "user_takeover_#{SecureRandom.hex(4)}",
      status: :recording,
      metadata: {
        "account_id" => @owner_account.id.to_s,
        "handoff_state" => {
          "url" => "https://example.com/checkout",
          "cookies" => [ { "name" => "_session", "value" => "sekrit-cookie" } ],
          "local_storage" => { "auth_token" => "lst-secret" },
          "session_storage" => { "csrf" => "sst-secret" }
        }
      }
    )

    @action = @recording.record_action!(
      action_type: "type",
      selector: "input[name=password]",
      value: "topsecret99",
      metadata: { "password" => "topsecret99", "url" => "https://example.com/login" }
    )
  end

  # ===========================================
  # IDOR — cross-account access must 404 (#106)
  # ===========================================

  test "show returns 404 for a recording owned by another account" do
    sign_in_as(@intruder)

    get "/api/session_recordings/#{@recording.id}"

    assert_response :not_found
    assert_not_includes response.body, "topsecret99"
  end

  test "actions returns 404 for a recording owned by another account" do
    sign_in_as(@intruder)

    get "/api/session_recordings/#{@recording.id}/actions"

    assert_response :not_found
  end

  test "snapshot returns 404 for a recording owned by another account" do
    sign_in_as(@intruder)

    get "/api/session_recordings/#{@recording.id}/snapshot/#{@action.id}"

    assert_response :not_found
  end

  test "export returns 404 for a recording owned by another account" do
    sign_in_as(@intruder)

    post "/api/session_recordings/#{@recording.id}/export"

    assert_response :not_found
    assert_not_includes response.body, "topsecret99"
  end

  test "handoff returns 404 for a recording owned by another account" do
    sign_in_as(@intruder)

    assert_no_difference -> { SessionRecording.count } do
      post "/api/session_recordings/#{@recording.id}/handoff"
    end

    assert_response :not_found
    assert_not_includes response.body, "sekrit-cookie"
  end

  # ===========================================
  # The owner is unaffected by the gate
  # ===========================================

  test "show still returns 200 for the owning account" do
    sign_in_as(@owner)

    get "/api/session_recordings/#{@recording.id}"

    assert_response :success
    assert_equal @recording.id, json_response["recording"]["id"]
  end

  test "actions still returns 200 for the owning account" do
    sign_in_as(@owner)

    get "/api/session_recordings/#{@recording.id}/actions"

    assert_response :success
    assert_equal 1, json_response["actions"].size
  end

  test "export still returns 200 for the owning account" do
    sign_in_as(@owner)

    post "/api/session_recordings/#{@recording.id}/export"

    assert_response :success
    assert_equal 1, json_response["cassette"]["actions"].size
  end

  test "handoff still returns 200 for the owning account" do
    sign_in_as(@owner)

    post "/api/session_recordings/#{@recording.id}/handoff"

    assert_response :success
    assert json_response["continuation_recording_id"].present?
  end

  test "handoff returns the full handoff_state to the owner, unscrubbed" do
    sign_in_as(@owner)

    post "/api/session_recordings/#{@recording.id}/handoff"

    assert_response :success
    handoff_state = json_response["handoff_state"]
    assert_equal "sekrit-cookie", handoff_state["cookies"].first["value"]
    assert_equal "lst-secret", handoff_state["local_storage"]["auth_token"]
  end

  test "snapshot still returns 200 for the owning account" do
    sign_in_as(@owner)

    get "/api/session_recordings/#{@recording.id}/snapshot/#{@action.id}"

    assert_response :success
    assert_equal "screenshot", json_response["type"]
  end

  test "admins may still read another account's recording" do
    admin = create_user(email: "recording-admin-#{SecureRandom.hex(4)}@example.com")
    admin.update!(admin: true)
    sign_in_as(admin)

    get "/api/session_recordings/#{@recording.id}"

    assert_response :success
  end

  # ==================================================
  # lander_demo — public to READ only. The carve-out
  # must not reach export, handoff or destroy (#119)
  # ==================================================

  test "any signed-in user may read the lander demo recording" do
    demo = SessionRecording.create!(name: "lander_demo", status: :completed, metadata: {})
    sign_in_as(@intruder)

    get "/api/session_recordings/#{demo.id}"

    assert_response :success
    assert_equal demo.id, json_response["recording"]["id"]
  end

  test "any signed-in user may read the lander demo action timeline" do
    demo = create_lander_demo
    sign_in_as(@intruder)

    get "/api/session_recordings/#{demo.id}/actions"

    assert_response :success
    assert_equal 1, json_response["actions"].size
  end

  test "any signed-in user may read a lander demo snapshot" do
    demo = create_lander_demo
    sign_in_as(@intruder)

    get "/api/session_recordings/#{demo.id}/snapshot/#{demo.recording_actions.first.id}"

    assert_response :success
    assert_equal "screenshot", json_response["type"]
  end

  test "reading the lander demo still scrubs its handoff secrets" do
    demo = create_lander_demo
    sign_in_as(@intruder)

    get "/api/session_recordings/#{demo.id}"

    assert_response :success
    assert_not_includes response.body, "demo-sekrit-cookie"
    assert_not_includes response.body, "demo-lst-secret"
    assert_not_includes response.body, "demo-sst-secret"
  end

  test "non-owners cannot export the lander demo recording" do
    demo = create_lander_demo
    sign_in_as(@intruder)

    post "/api/session_recordings/#{demo.id}/export"

    assert_response :not_found
    assert_nil json_response["cassette"]
  end

  test "non-owners cannot hand off the lander demo recording" do
    demo = create_lander_demo
    sign_in_as(@intruder)
    recording_count = SessionRecording.count

    post "/api/session_recordings/#{demo.id}/handoff"

    assert_response :not_found
    assert_nil json_response["handoff_state"]
    assert_not_includes response.body, "demo-sekrit-cookie"
    assert_not_includes response.body, "demo-lst-secret"
    assert_not_includes response.body, "demo-sst-secret"
    assert_equal recording_count, SessionRecording.count,
                 "handoff must not create a continuation recording for a non-owner"
  end

  test "the owning account may still export and hand off the lander demo" do
    demo = create_lander_demo
    sign_in_as(@owner)

    post "/api/session_recordings/#{demo.id}/export"
    assert_response :success
    assert_equal 1, json_response["cassette"]["actions"].size

    post "/api/session_recordings/#{demo.id}/handoff"
    assert_response :success
    assert_equal "demo-sekrit-cookie", json_response["handoff_state"]["cookies"].first["value"]
  end

  test "admins may still export and hand off the lander demo" do
    demo = create_lander_demo
    admin = create_user(email: "recording-admin-#{SecureRandom.hex(4)}@example.com")
    admin.update!(admin: true)
    sign_in_as(admin)

    post "/api/session_recordings/#{demo.id}/export"
    assert_response :success

    post "/api/session_recordings/#{demo.id}/handoff"
    assert_response :success
  end

  test "non-admins cannot delete the lander demo recording" do
    demo = SessionRecording.create!(name: "lander_demo", status: :completed, metadata: {})
    sign_in_as(@intruder)

    assert_no_difference -> { SessionRecording.count } do
      delete "/api/session_recordings/#{demo.id}"
    end

    assert_response :forbidden
  end

  # ===========================================
  # Redaction — show/export must not leak (#110)
  # ===========================================

  test "show timeline redacts sensitive action values and metadata" do
    sign_in_as(@owner)

    get "/api/session_recordings/#{@recording.id}"

    assert_response :success
    entry = json_response["recording"]["timeline"].first

    assert_equal "[REDACTED]", entry["value"]
    assert_not_includes response.body, "topsecret99"
    assert_nil entry["metadata"]["password"]
    assert_equal "https://example.com/login", entry["metadata"]["url"]
  end

  test "export cassette redacts sensitive action values and metadata" do
    sign_in_as(@owner)

    post "/api/session_recordings/#{@recording.id}/export"

    assert_response :success
    exported = json_response["cassette"]["actions"].first

    assert_equal "[REDACTED]", exported["value"]
    assert_not_includes response.body, "topsecret99"
    assert_nil exported["metadata"]["password"]
    assert_equal "https://example.com/login", exported["metadata"]["url"]
  end

  test "show strips cookies and web storage from nested handoff_state" do
    sign_in_as(@owner)

    get "/api/session_recordings/#{@recording.id}"

    assert_response :success
    handoff_state = json_response["recording"]["handoff_state"]

    assert_equal "https://example.com/checkout", handoff_state["url"]
    assert_nil handoff_state["cookies"]
    assert_nil handoff_state["local_storage"]
    assert_nil handoff_state["session_storage"]
    assert_not_includes response.body, "sekrit-cookie"
    assert_not_includes response.body, "lst-secret"
    assert_not_includes response.body, "sst-secret"
  end

  private

  # A lander demo that carries the same class of secrets as any other
  # recording, owned by @owner_account so @intruder exercises the carve-out.
  def create_lander_demo
    demo = SessionRecording.create!(
      name: "lander_demo",
      status: :recording,
      metadata: {
        "account_id" => @owner_account.id.to_s,
        "handoff_state" => {
          "url" => "https://example.com/demo",
          "cookies" => [ { "name" => "_session", "value" => "demo-sekrit-cookie" } ],
          "local_storage" => { "auth_token" => "demo-lst-secret" },
          "session_storage" => { "csrf" => "demo-sst-secret" }
        }
      }
    )

    demo.record_action!(
      action_type: "click",
      selector: "button.cta",
      value: "Start the demo",
      metadata: { "url" => "https://example.com/demo" }
    )

    demo.complete!
    demo.reload
  end
end
