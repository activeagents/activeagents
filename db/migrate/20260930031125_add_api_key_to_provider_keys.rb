# frozen_string_literal: true

# Host-based providers (Ollama) can sit behind an authenticating proxy or
# be Ollama Cloud; the optional api_key is sent as a Bearer token alongside
# the host URL stored in credential. Encrypted like credential.
class AddApiKeyToProviderKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :provider_keys, :api_key, :string
  end
end
