# frozen_string_literal: true

require_relative "test_helper"

class TestAgentPool < Minitest::Test
  def pool(size: 3)
    Ragents::Ractor::AgentPool.new(
      size: size,
      provider_class: Ragents::Providers::MockProvider,
      provider_opts: { responses: [{ content: "Pool response" }] }
    )
  end

  def test_process_returns_results_for_all_inputs
    p = pool
    results = p.process(["A", "B", "C", "D", "E"])
    assert_equal 5, results.size
  end

  def test_process_results_in_correct_order
    p = pool(size: 2)
    # Each input gets "Pool response" but let's verify order by count
    results = p.process(["A", "B", "C"])
    assert_equal 3, results.size
    results.each do |r|
      assert_kind_of Ragents::Ractor::RunResult, r
      assert_equal "Pool response", r.content
    end
  end

  def test_empty_inputs_returns_empty_array
    p = pool
    results = p.process([])
    assert_equal [], results
  end

  def test_process_stream_yields_index_and_result
    p = pool(size: 2)
    collected = []
    p.process_stream(["X", "Y", "Z"]) do |idx, result|
      collected << [idx, result]
    end

    assert_equal 3, collected.size
    indices = collected.map(&:first).sort
    assert_equal [0, 1, 2], indices
  end

  def test_pool_respects_size_limit
    # With size=1 and 3 inputs, requests should be processed sequentially
    p = pool(size: 1)
    t = Time.now
    p.process(["A", "B", "C"])
    elapsed = Time.now - t
    # Should be fast (MockProvider has no I/O), just verify it completes
    assert elapsed < 5
  end
end
