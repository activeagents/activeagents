# frozen_string_literal: true

# Captures provider prompt-cache hits and extended-thinking usage per
# generation (from ActiveAgent usage objects: cached_tokens /
# reasoning_tokens), backing the cache-hit and thinking indicators in the
# Interactions view.
class AddCacheAndReasoningTokensToAgentGenerations < ActiveRecord::Migration[8.2]
  def change
    add_column :agent_generations, :cached_tokens, :integer, default: 0
    add_column :agent_generations, :reasoning_tokens, :integer, default: 0
  end
end
