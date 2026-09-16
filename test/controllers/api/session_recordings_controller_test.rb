# frozen_string_literal: true

require "test_helper"

# Two surfaces for one model. The landing page's visitor flow stays on this
# app at /api/session_recordings (anonymous, write-token gated); everything a
# signed-in owner does with a recording is the mounted engine's, at
# /dashboard/api/session_recordings, scoped to the owner.
class Api::SessionRecordingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user(email: "recording-owner-#{SecureRandom.hex(4)}@example.com")
    @owner_account = create_account(owner: @owner)

    @intruder = create_user(email: "recording-intruder-#{SecureRandom.hex(4)}@example.com")
    @intruder_account = create_account(owner: @intruder)

    @recording = SessionRecording.create!(
      name: "user_takeover_#{SecureRandom.hex(4)}",
      status: :recording,
      owner: @owner,
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
  # Playback through the engine: owner-scoped, ids unenumerable
  # ===========================================

  test "show returns 404 for a recording owned by someone else" do
    sign_in_as(@intruder)

    get "/dashboard/api/session_recordings/#{@recording.id}"

    assert_response :not_found
    assert_not_includes response.body, "topsecret99"
  end

  test "actions returns 404 for a recording owned by someone else" do
    sign_in_as(@intruder)

    get "/dashboard/api/session_recordings/#{@recording.id}/actions"

    assert_response :not_found
  end

  test "show still returns 200 for the owner" do
    sign_in_as(@owner)

    get "/dashboard/api/session_recordings/#{@recording.id}"

    assert_response :success
    assert_equal @recording.id, json_response.dig("recording", "id")
  end

  test "the owner's list carries their recording and not someone else's" do
    other = SessionRecording.start_user_session!(visitor_id: "v_other", owner: @intruder)
    sign_in_as(@owner)

    get "/dashboard/api/session_recordings"

    assert_response :success
    ids = json_response["recordings"].map { |r| r["id"] }
    assert_includes ids, @recording.id
    assert_not_includes ids, other.id
  end

  test "a browser that is not signed in is sent to this app's sign-in page" do
    get "/dashboard/api/session_recordings/#{@recording.id}"

    assert_redirected_to "/session/new"
  end

  test "show timeline redacts sensitive action values and metadata" do
    sign_in_as(@owner)

    get "/dashboard/api/session_recordings/#{@recording.id}"

    assert_response :success
    assert_not_includes response.body, "topsecret99"
    assert_not_includes response.body, "sekrit-cookie"
  end

  # ===========================================
  # The landing page's visitor flow, on this app
  # ===========================================

  test "record_action refuses an anonymous caller who only knows the id" do
    post "/api/session_recordings/#{@recording.id}/record_action",
         params: { action_type: "click", selector: "button" }, as: :json

    assert_response :not_found
    assert_equal 1, @recording.recording_actions.count
  end

  test "complete refuses an anonymous caller who only knows the id" do
    post "/api/session_recordings/#{@recording.id}/complete", as: :json

    assert_response :not_found
    assert @recording.reload.recording?
  end

  test "an unknown id and someone else's id answer identically to anonymous writers" do
    post "/api/session_recordings/999999999/record_action", params: { action_type: "click" }, as: :json
    unknown = response.status

    post "/api/session_recordings/#{@recording.id}/record_action", params: { action_type: "click" }, as: :json

    assert_equal unknown, response.status, "a real id must not be distinguishable from a bogus one"
  end

  test "start_user_session issues a token that authorizes writes to that recording only" do
    post "/api/session_recordings/start_user_session", params: { page_url: "https://activeagents.ai/" }, as: :json
    assert_response :created
    token = json_response["recording_token"]
    recording_id = json_response["recording_id"]
    assert token.present?

    post "/api/session_recordings/#{recording_id}/record_action",
         params: { action_type: "click", selector: "button", recording_token: token }, as: :json
    assert_response :success

    # The same token does not open someone else's recording.
    post "/api/session_recordings/#{@recording.id}/record_action",
         params: { action_type: "click", selector: "button", recording_token: token }, as: :json
    assert_response :not_found

    post "/api/session_recordings/#{recording_id}/complete", params: { recording_token: token }, as: :json
    assert_response :success
    assert_equal "completed", json_response["status"]
  end

  test "the write token is also accepted as a header" do
    post "/api/session_recordings/start_user_session", as: :json
    token = json_response["recording_token"]
    recording_id = json_response["recording_id"]

    post "/api/session_recordings/#{recording_id}/record_action",
         params: { action_type: "scroll" }, headers: { "X-Recording-Token" => token }, as: :json

    assert_response :success
  end

  test "a forged or tampered token does not authorize writes" do
    post "/api/session_recordings/start_user_session", as: :json
    token = json_response["recording_token"]
    recording_id = json_response["recording_id"]

    post "/api/session_recordings/#{recording_id}/record_action",
         params: { action_type: "click", recording_token: "#{token}x" }, as: :json
    assert_response :not_found

    post "/api/session_recordings/#{recording_id}/record_action",
         params: { action_type: "click", recording_token: "not-a-token" }, as: :json
    assert_response :not_found
  end

  test "the owner may still write to their recording without a token" do
    sign_in_as(@owner)

    assert_difference -> { @recording.recording_actions.count }, 1 do
      post "/api/session_recordings/#{@recording.id}/record_action",
           params: { action_type: "click", selector: "button" }, as: :json
    end
    assert_response :success
  end

  test "another signed-in account may not write to the recording" do
    sign_in_as(@intruder)

    post "/api/session_recordings/#{@recording.id}/record_action",
         params: { action_type: "click" }, as: :json

    assert_response :not_found
  end

  test "a token holder still learns when the recording is already complete" do
    post "/api/session_recordings/start_user_session", as: :json
    token = json_response["recording_token"]
    recording_id = json_response["recording_id"]
    SessionRecording.find(recording_id).complete!

    post "/api/session_recordings/#{recording_id}/record_action",
         params: { action_type: "click", recording_token: token }, as: :json

    assert_response :unprocessable_entity
    assert_match(/already completed/, json_response["error"])
  end

  test "a signed-in visitor's user session is owned by them and stamped with their account" do
    sign_in_as(@owner)

    post "/api/session_recordings/start_user_session", as: :json

    assert_response :created
    recording = SessionRecording.find(json_response["recording_id"])
    assert_equal @owner, recording.owner
    assert_equal @owner_account.id.to_s, recording.metadata["account_id"]
  end
end
