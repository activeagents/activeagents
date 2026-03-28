# frozen_string_literal: true

# HuggingFaceService - Integration with Hugging Face Inference API
#
# Provides text generation, embeddings, and model management via the
# Hugging Face API. Can be used as a provider for agent execution
# or standalone for embedding/classification tasks.
#
# Usage:
#   service = HuggingFaceService.new
#   result = service.generate(model: "meta-llama/Llama-3-8B-Instruct", prompt: "Hello")
#   embeddings = service.embeddings(text: "Some text to embed")
#   classification = service.classify(text: "Is this spam?", labels: ["spam", "not_spam"])
#
class HuggingFaceService
  class HuggingFaceError < StandardError; end
  class RateLimitError < HuggingFaceError; end
  class ModelNotFoundError < HuggingFaceError; end

  BASE_URL = "https://api-inference.huggingface.co"
  DEFAULT_EMBEDDING_MODEL = "sentence-transformers/all-MiniLM-L6-v2"
  DEFAULT_GENERATION_MODEL = "meta-llama/Llama-3.1-8B-Instruct"

  def initialize(api_key: nil)
    @api_key = api_key || Rails.application.credentials.dig(:hugging_face, :api_key) || ENV["HUGGINGFACE_API_KEY"]
  end

  def configured?
    @api_key.present?
  end

  # Text generation using Hugging Face Inference API
  def generate(prompt:, model: DEFAULT_GENERATION_MODEL, max_tokens: 1024, temperature: 0.7, **options)
    ensure_configured!

    payload = {
      inputs: prompt,
      parameters: {
        max_new_tokens: max_tokens,
        temperature: temperature,
        return_full_text: false
      }.merge(options.slice(:top_p, :top_k, :repetition_penalty))
    }

    response = post("/models/#{model}", payload)

    if response.is_a?(Array) && response.first
      {
        content: response.first["generated_text"],
        model: model,
        provider: "hugging_face"
      }
    else
      raise HuggingFaceError, "Unexpected response format"
    end
  end

  # Generate embeddings for text
  def embeddings(text:, model: DEFAULT_EMBEDDING_MODEL)
    ensure_configured!

    payload = { inputs: text }
    response = post("/models/#{model}", payload)

    {
      embedding: response,
      model: model,
      dimensions: response.is_a?(Array) ? response.length : nil
    }
  end

  # Batch embeddings for multiple texts
  def batch_embeddings(texts:, model: DEFAULT_EMBEDDING_MODEL)
    ensure_configured!

    payload = { inputs: texts }
    response = post("/models/#{model}", payload)

    {
      embeddings: response,
      model: model,
      count: texts.length
    }
  end

  # Zero-shot classification
  def classify(text:, labels:, model: "facebook/bart-large-mnli")
    ensure_configured!

    payload = {
      inputs: text,
      parameters: { candidate_labels: labels }
    }

    response = post("/models/#{model}", payload)

    {
      labels: response["labels"],
      scores: response["scores"],
      sequence: response["sequence"],
      model: model
    }
  end

  # Compute cosine similarity between two embeddings
  def self.cosine_similarity(vec_a, vec_b)
    return 0.0 if vec_a.nil? || vec_b.nil? || vec_a.empty? || vec_b.empty?

    dot_product = vec_a.zip(vec_b).sum { |a, b| a * b }
    magnitude_a = Math.sqrt(vec_a.sum { |a| a**2 })
    magnitude_b = Math.sqrt(vec_b.sum { |b| b**2 })

    return 0.0 if magnitude_a.zero? || magnitude_b.zero?

    dot_product / (magnitude_a * magnitude_b)
  end

  # List available models (filtered by task)
  def list_models(task: nil, search: nil, limit: 20)
    ensure_configured!

    params = { limit: limit, sort: "downloads", direction: -1 }
    params[:pipeline_tag] = task if task
    params[:search] = search if search

    query = params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
    get("/api/models?#{query}")
  end

  private

  def ensure_configured!
    raise HuggingFaceError, "Hugging Face API key not configured. Set HUGGINGFACE_API_KEY or add to credentials." unless configured?
  end

  def post(path, payload)
    request(:post, path, payload)
  end

  def get(path)
    request(:get, path)
  end

  def request(method, path, payload = nil)
    require "net/http"

    uri = URI("#{BASE_URL}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 120 # Models can take time to load

    req = case method
    when :post
      r = Net::HTTP::Post.new(uri)
      r.body = payload.to_json
      r
    when :get
      Net::HTTP::Get.new(uri)
    end

    req["Authorization"] = "Bearer #{@api_key}"
    req["Content-Type"] = "application/json"

    response = http.request(req)
    body = JSON.parse(response.body)

    case response.code.to_i
    when 200
      body
    when 429
      raise RateLimitError, "Rate limit exceeded. Retry after: #{response['Retry-After']}"
    when 404
      raise ModelNotFoundError, "Model not found: #{path}"
    when 503
      # Model is loading
      if body.is_a?(Hash) && body["error"]&.include?("loading")
        estimated_time = body["estimated_time"] || 30
        raise HuggingFaceError, "Model is loading. Estimated time: #{estimated_time}s"
      end
      raise HuggingFaceError, "Service unavailable: #{body}"
    else
      error_msg = body.is_a?(Hash) ? body["error"] : body.to_s
      raise HuggingFaceError, "API error (#{response.code}): #{error_msg}"
    end
  rescue JSON::ParserError
    raise HuggingFaceError, "Invalid response from API"
  end
end
