# frozen_string_literal: true

require "test_helper"

class AgentFragmentTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @agent = create_agent(user: @user)
    @context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid)
  end

  test "belongs to agent_context" do
    fragment = @context.agent_fragments.create!(
      content: "test",
      content_hash: Digest::SHA256.hexdigest("test"),
      fragment_type: "message"
    )

    assert_equal @context, fragment.agent_context
  end

  test "has many reasons" do
    fragment = @context.agent_fragments.create!(
      content: "test",
      content_hash: Digest::SHA256.hexdigest("test"),
      fragment_type: "message"
    )

    reason = fragment.agent_reasons.create!(
      reason_type: "cached_generation",
      explanation: "test reason",
      confidence: 1.0
    )

    assert_includes fragment.agent_reasons, reason
  end

  test "auto-computes content hash" do
    fragment = @context.agent_fragments.create!(
      content: "auto hash test",
      fragment_type: "message"
    )

    assert_equal Digest::SHA256.hexdigest("auto hash test"), fragment.content_hash
  end

  test "content_hash is unique per context" do
    @context.agent_fragments.create!(
      content: "duplicate",
      content_hash: Digest::SHA256.hexdigest("duplicate"),
      fragment_type: "message"
    )

    duplicate = @context.agent_fragments.build(
      content: "duplicate",
      content_hash: Digest::SHA256.hexdigest("duplicate"),
      fragment_type: "message"
    )

    assert_not duplicate.valid?
  end

  test "validates fragment_type" do
    fragment = @context.agent_fragments.build(
      content: "test",
      content_hash: Digest::SHA256.hexdigest("test"),
      fragment_type: "invalid_type"
    )

    assert_not fragment.valid?
  end

  test "allows nil fragment_type" do
    fragment = @context.agent_fragments.create!(
      content: "test",
      content_hash: Digest::SHA256.hexdigest("test"),
      fragment_type: nil
    )

    assert fragment.valid?
  end

  test "deterministic? returns true when cached_generation reason exists" do
    fragment = @context.agent_fragments.create!(
      content: "test",
      content_hash: Digest::SHA256.hexdigest("test"),
      fragment_type: "generation_input"
    )

    fragment.agent_reasons.create!(
      reason_type: "cached_generation",
      explanation: "cached",
      confidence: 1.0,
      evidence: { "cached_response" => "output" }
    )

    assert fragment.deterministic?
  end

  test "deterministic? returns false without cached_generation reason" do
    fragment = @context.agent_fragments.create!(
      content: "test",
      content_hash: Digest::SHA256.hexdigest("test"),
      fragment_type: "message"
    )

    assert_not fragment.deterministic?
  end

  test "cached_response returns the stored response" do
    fragment = @context.agent_fragments.create!(
      content: "test",
      content_hash: Digest::SHA256.hexdigest("test"),
      fragment_type: "generation_input"
    )

    fragment.agent_reasons.create!(
      reason_type: "cached_generation",
      confidence: 1.0,
      evidence: { "cached_response" => "hello from cache" }
    )

    assert_equal "hello from cache", fragment.cached_response
  end

  test "by_type scope filters fragments" do
    @context.agent_fragments.create!(
      content: "msg",
      content_hash: Digest::SHA256.hexdigest("msg"),
      fragment_type: "message"
    )
    @context.agent_fragments.create!(
      content: "tool",
      content_hash: Digest::SHA256.hexdigest("tool"),
      fragment_type: "tool_result"
    )

    messages = @context.agent_fragments.by_type("message")
    assert_equal 1, messages.count
    assert_equal "message", messages.first.fragment_type
  end
end
