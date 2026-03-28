# frozen_string_literal: true

require "test_helper"

class DeterministicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @agent = create_agent(user: @user)
  end

  test "deterministic_actions defaults to empty" do
    assert_equal [], @agent.deterministic_actions
  end

  test "setting deterministic_actions stores in model_config" do
    @agent.deterministic_actions = %w[summarize classify]
    @agent.save!
    @agent.reload

    assert_equal %w[summarize classify], @agent.deterministic_actions
  end

  test "deterministic_action? returns true for configured actions" do
    @agent.deterministic_actions = %w[summarize]
    assert @agent.deterministic_action?("summarize")
    assert_not @agent.deterministic_action?("other")
  end

  test "generate_with_caching skips cache for non-deterministic actions" do
    result = @agent.generate_with_caching("not_deterministic", "test prompt")

    # Should fall through to normal execution (mock)
    assert result[:output].present?
    assert_nil result.dig(:metadata, :cached)
  end

  test "generate_with_caching returns cached response on second call" do
    @agent.deterministic_actions = %w[summarize]
    @agent.save!

    # First call - cache miss
    result1 = @agent.generate_with_caching("summarize", "test prompt", session_id: "test-session")
    assert_equal false, result1.dig(:metadata, :cached)
    assert result1[:output].present?

    # Second call with same input - cache hit
    result2 = @agent.generate_with_caching("summarize", "test prompt", session_id: "test-session")
    assert_equal true, result2.dig(:metadata, :cached)
    assert_equal result1[:output], result2[:output]
    # Cached responses have zero token usage
    assert_equal 0, result2.dig(:usage, :total_tokens)
  end

  test "generate_with_caching creates context and fragment" do
    @agent.deterministic_actions = %w[summarize]
    @agent.save!

    assert_difference "AgentContext.count", 1 do
      assert_difference "AgentFragment.count", 1 do
        @agent.generate_with_caching("summarize", "test", session_id: "new-session")
      end
    end
  end

  test "generate_with_caching uses existing context for same session" do
    @agent.deterministic_actions = %w[summarize]
    @agent.save!

    @agent.generate_with_caching("summarize", "test1", session_id: "shared-session")

    assert_no_difference "AgentContext.count" do
      @agent.generate_with_caching("summarize", "test2", session_id: "shared-session")
    end
  end
end
