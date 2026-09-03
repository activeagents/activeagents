# frozen_string_literal: true

require "test_helper"

class SessionRecordingTest < ActiveSupport::TestCase
  setup do
    @recording = SessionRecording.create!(
      name: "user_takeover_#{SecureRandom.hex(4)}",
      status: :recording,
      metadata: {}
    )
  end

  test "timeline redacts values captured from sensitive selectors" do
    @recording.record_action!(
      action_type: "type",
      selector: "input[name=password]",
      value: "topsecret99"
    )

    entry = @recording.timeline.first

    assert_equal "[REDACTED]", entry[:value]
  end

  test "timeline redacts values that are themselves sensitive" do
    @recording.record_action!(
      action_type: "type",
      selector: "input[name=card]",
      value: "4111111111111111"
    )

    assert_equal "[REDACTED]", @recording.timeline.first[:value]
  end

  test "timeline strips sensitive keys from per-action metadata" do
    @recording.record_action!(
      action_type: "form_fill",
      selector: "form#checkout",
      value: "submitted",
      metadata: { "password" => "topsecret99", "cvv" => "123", "url" => "https://example.com" }
    )

    metadata = @recording.timeline.first[:metadata]

    assert_nil metadata["password"]
    assert_nil metadata["cvv"]
    assert_equal "https://example.com", metadata["url"]
  end

  test "timeline leaves non-sensitive values intact" do
    @recording.record_action!(
      action_type: "navigate",
      selector: nil,
      value: "https://example.com/pricing"
    )

    assert_equal "https://example.com/pricing", @recording.timeline.first[:value]
  end
end
