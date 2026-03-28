# frozen_string_literal: true

require "test_helper"

class AgentContextTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @agent = create_agent(user: @user)
  end

  # ===========================================
  # Association Tests
  # ===========================================

  test "belongs to agent" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid)
    assert_equal @agent, context.agent
  end

  test "has many fragments" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid)
    fragment = context.agent_fragments.create!(
      content: "test content",
      content_hash: Digest::SHA256.hexdigest("test content"),
      fragment_type: "message"
    )

    assert_includes context.agent_fragments, fragment
  end

  test "destroys fragments when deleted" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid)
    context.agent_fragments.create!(
      content: "test content",
      content_hash: Digest::SHA256.hexdigest("test content"),
      fragment_type: "message"
    )

    assert_difference "AgentFragment.count", -1 do
      context.destroy
    end
  end

  # ===========================================
  # Validation Tests
  # ===========================================

  test "requires session_id" do
    context = @agent.agent_contexts.build(session_id: nil)
    # session_id is auto-generated if nil
    assert context.valid?
    assert context.session_id.present?
  end

  test "session_id must be unique" do
    session_id = SecureRandom.uuid
    @agent.agent_contexts.create!(session_id: session_id)

    duplicate = @agent.agent_contexts.build(session_id: session_id)
    assert_not duplicate.valid?
  end

  # ===========================================
  # Fragment Management
  # ===========================================

  test "add_fragment creates a new fragment" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid)

    fragment = context.add_fragment(content: "Hello world", type: "message")

    assert fragment.persisted?
    assert_equal "Hello world", fragment.content
    assert_equal "message", fragment.fragment_type
    assert fragment.content_hash.present?
    assert fragment.token_count.present?
  end

  test "add_fragment deduplicates by content hash" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid)

    fragment1 = context.add_fragment(content: "same content")
    fragment2 = context.add_fragment(content: "same content")

    assert_equal fragment1.id, fragment2.id
    assert_equal 1, context.agent_fragments.count
  end

  test "add_fragment stores metadata" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid)

    fragment = context.add_fragment(
      content: "test",
      type: "tool_result",
      metadata: { tool: "fetch", url: "https://example.com" }
    )

    assert_equal "fetch", fragment.metadata["tool"]
    assert_equal "https://example.com", fragment.metadata["url"]
  end

  # ===========================================
  # Deterministic Cache
  # ===========================================

  test "cache_generation stores input and output" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid)

    fragment = context.cache_generation(
      input: "test input hash",
      output: "cached response"
    )

    assert fragment.persisted?
    assert_equal 1, fragment.agent_reasons.count
    assert_equal "cached_generation", fragment.agent_reasons.first.reason_type
  end

  test "deterministic_response returns cached output" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid)

    context.cache_generation(input: "my_key", output: "cached output")

    input_hash = Digest::SHA256.hexdigest("my_key")
    result = context.deterministic_response(input_hash)
    assert_equal "cached output", result
  end

  test "deterministic_response returns nil for unknown input" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid)

    result = context.deterministic_response("nonexistent")
    assert_nil result
  end

  # ===========================================
  # State Management
  # ===========================================

  test "update_state persists key-value pairs" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid)

    context.update_state("step", 2)
    context.update_state("user_name", "Alice")

    context.reload
    assert_equal 2, context.get_state("step")
    assert_equal "Alice", context.get_state("user_name")
  end

  # ===========================================
  # Expiration Tests
  # ===========================================

  test "active scope excludes expired contexts" do
    active = @agent.agent_contexts.create!(session_id: SecureRandom.uuid, expires_at: 1.hour.from_now)
    expired = @agent.agent_contexts.create!(session_id: SecureRandom.uuid, expires_at: 1.hour.ago)

    assert_includes AgentContext.active, active
    assert_not_includes AgentContext.active, expired
  end

  test "expired? returns true for expired contexts" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid, expires_at: 1.hour.ago)
    assert context.expired?
  end

  test "expired? returns false for active contexts" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid, expires_at: 1.hour.from_now)
    assert_not context.expired?
  end

  test "contexts without expiry are always active" do
    context = @agent.agent_contexts.create!(session_id: SecureRandom.uuid, expires_at: nil)
    assert context.active?
    assert_not context.expired?
  end
end
