# frozen_string_literal: true

require "test_helper"

class AgentReasonTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @agent = create_agent(user: @user)
    @context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid)
    @fragment = @context.agent_fragments.create!(
      content: "test",
      content_hash: Digest::SHA256.hexdigest("test"),
      fragment_type: "message"
    )
  end

  test "belongs to agent_fragment" do
    reason = @fragment.agent_reasons.create!(
      reason_type: "cached_generation",
      explanation: "test"
    )

    assert_equal @fragment, reason.agent_fragment
  end

  test "validates reason_type presence" do
    reason = @fragment.agent_reasons.build(reason_type: nil)
    assert_not reason.valid?
  end

  test "validates reason_type inclusion" do
    reason = @fragment.agent_reasons.build(reason_type: "invalid")
    assert_not reason.valid?
  end

  test "allows all valid reason types" do
    AgentReason::REASON_TYPES.each do |type|
      reason = @fragment.agent_reasons.build(reason_type: type, explanation: "test")
      assert reason.valid?, "#{type} should be a valid reason type"
    end
  end

  test "for_fragment creates reason with calculated confidence" do
    reason = AgentReason.for_fragment(
      @fragment,
      type: "cached_generation",
      explanation: "exact cache match",
      evidence: { "cached_response" => "hello" }
    )

    assert reason.persisted?
    assert_equal 1.0, reason.confidence
    assert_equal "cached_generation", reason.reason_type
  end

  test "for_fragment calculates confidence by type" do
    types_and_expected = {
      "cached_generation" => 1.0,
      "tool_result" => 0.95,
      "business_rule" => 0.9,
      "user_preference" => 0.85,
      "semantic_match" => 0.8
    }

    types_and_expected.each do |type, expected_confidence|
      reason = AgentReason.for_fragment(
        @fragment,
        type: type,
        explanation: "test #{type}"
      )

      assert_equal expected_confidence, reason.confidence,
        "#{type} should have confidence #{expected_confidence}"
    end
  end

  test "semantic_match uses similarity_score from evidence" do
    reason = AgentReason.for_fragment(
      @fragment,
      type: "semantic_match",
      explanation: "similar content",
      evidence: { "similarity_score" => 0.92 }
    )

    assert_equal 0.92, reason.confidence
  end

  test "apply returns cached_response for cached_generation" do
    reason = @fragment.agent_reasons.create!(
      reason_type: "cached_generation",
      evidence: { "cached_response" => "cached output" },
      confidence: 1.0
    )

    assert_equal "cached output", reason.apply
  end

  test "apply returns tool_output for tool_result" do
    reason = @fragment.agent_reasons.create!(
      reason_type: "tool_result",
      evidence: { "tool_output" => "tool result data" },
      confidence: 0.95
    )

    assert_equal "tool result data", reason.apply
  end

  test "apply returns fragment content for semantic_match" do
    reason = @fragment.agent_reasons.create!(
      reason_type: "semantic_match",
      confidence: 0.85
    )

    assert_equal "test", reason.apply
  end

  test "high_confidence scope filters by threshold" do
    low = @fragment.agent_reasons.create!(
      reason_type: "semantic_match",
      confidence: 0.5
    )
    high = @fragment.agent_reasons.create!(
      reason_type: "cached_generation",
      confidence: 0.95
    )

    results = AgentReason.high_confidence
    assert_includes results, high
    assert_not_includes results, low
  end
end
