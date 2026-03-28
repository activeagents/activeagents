# frozen_string_literal: true

require "test_helper"

class HuggingFaceServiceTest < ActiveSupport::TestCase
  test "initializes without API key" do
    service = HuggingFaceService.new(api_key: nil)
    assert_not service.configured?
  end

  test "initializes with API key" do
    service = HuggingFaceService.new(api_key: "hf_test_key")
    assert service.configured?
  end

  test "generate raises when not configured" do
    service = HuggingFaceService.new(api_key: nil)

    assert_raises(HuggingFaceService::HuggingFaceError) do
      service.generate(prompt: "Hello")
    end
  end

  test "embeddings raises when not configured" do
    service = HuggingFaceService.new(api_key: nil)

    assert_raises(HuggingFaceService::HuggingFaceError) do
      service.embeddings(text: "test")
    end
  end

  test "classify raises when not configured" do
    service = HuggingFaceService.new(api_key: nil)

    assert_raises(HuggingFaceService::HuggingFaceError) do
      service.classify(text: "test", labels: [ "a", "b" ])
    end
  end

  test "cosine_similarity computes correctly for identical vectors" do
    vec = [ 1.0, 0.0, 0.0 ]
    assert_in_delta 1.0, HuggingFaceService.cosine_similarity(vec, vec), 0.001
  end

  test "cosine_similarity computes correctly for orthogonal vectors" do
    vec_a = [ 1.0, 0.0, 0.0 ]
    vec_b = [ 0.0, 1.0, 0.0 ]
    assert_in_delta 0.0, HuggingFaceService.cosine_similarity(vec_a, vec_b), 0.001
  end

  test "cosine_similarity computes correctly for opposite vectors" do
    vec_a = [ 1.0, 0.0 ]
    vec_b = [ -1.0, 0.0 ]
    assert_in_delta(-1.0, HuggingFaceService.cosine_similarity(vec_a, vec_b), 0.001)
  end

  test "cosine_similarity handles empty vectors" do
    assert_equal 0.0, HuggingFaceService.cosine_similarity([], [])
    assert_equal 0.0, HuggingFaceService.cosine_similarity(nil, nil)
  end

  test "cosine_similarity handles zero vectors" do
    vec_zero = [ 0.0, 0.0, 0.0 ]
    vec = [ 1.0, 2.0, 3.0 ]
    assert_equal 0.0, HuggingFaceService.cosine_similarity(vec_zero, vec)
  end

  test "default models are set" do
    assert HuggingFaceService::DEFAULT_EMBEDDING_MODEL.present?
    assert HuggingFaceService::DEFAULT_GENERATION_MODEL.present?
  end
end
