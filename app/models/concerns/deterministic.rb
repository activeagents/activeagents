# frozen_string_literal: true

# Deterministic - Generatively Deterministic pattern
#
# Enables agents to cache generation results and replay them deterministically.
# When an agent action is marked as deterministic, the system checks for a
# cached response before making an LLM call. If a matching fragment with a
# cached_generation reason exists, the cached output is returned instead.
#
# Usage in Agent model:
#   class Agent
#     include Deterministic
#   end
#
#   agent.deterministic_actions = ["summarize", "classify"]
#   agent.generate_with_caching("summarize", input_prompt, session_id: "abc")
#
module Deterministic
  extend ActiveSupport::Concern

  included do
    # Store deterministic action names as a JSON array on the agent
    # (uses the existing model_config jsonb column)
  end

  # Execute with deterministic caching: check cache first, fall back to generation
  def generate_with_caching(action_name, input_prompt, session_id: nil, **params)
    return build_and_execute_agent(input_prompt, **params) unless deterministic_action?(action_name)

    context = find_or_create_context(session_id)
    cache_key = compute_cache_key(action_name, input_prompt, params)

    # Check for cached response
    cached = context.deterministic_response(cache_key)
    if cached
      return {
        output: cached,
        metadata: { provider: provider, model: model, cached: true, cache_key: cache_key },
        usage: { input_tokens: 0, output_tokens: 0, total_tokens: 0 }
      }
    end

    # Generate and cache
    result = build_and_execute_agent(input_prompt, **params)

    if result[:output].present?
      context.cache_generation(input: cache_key, output: result[:output])
      result[:metadata] = result[:metadata].merge(cached: false, cache_key: cache_key)
    end

    result
  end

  def deterministic_actions
    model_config&.dig("deterministic_actions") || []
  end

  def deterministic_actions=(actions)
    self.model_config = (model_config || {}).merge("deterministic_actions" => Array(actions))
  end

  def deterministic_action?(action_name)
    deterministic_actions.include?(action_name.to_s)
  end

  private

  def find_or_create_context(session_id)
    session_id ||= SecureRandom.uuid
    agent_contexts.find_or_create_by!(session_id: session_id)
  end

  def compute_cache_key(action_name, input_prompt, params)
    Digest::SHA256.hexdigest([
      self.class.name,
      id,
      action_name,
      input_prompt,
      params.to_json
    ].join("|"))
  end
end
