# frozen_string_literal: true

# Platform API keys (Settings -> API Keys) and per-account LLM provider
# credentials. Both store their secret material through Active Record
# Encryption (see config/initializers/active_record_encryption.rb):
#
# - api_keys.token is encrypted deterministically so ingest auth can look a
#   key up with find_by(token:).
# - provider_keys.credential is encrypted non-deterministically (never
#   queried by value). It holds an API key for key-based providers and a
#   host URL for ollama.
class CreateApiKeysAndProviderKeys < ActiveRecord::Migration[8.2]
  def change
    create_table :api_keys do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token, null: false
      t.string :token_prefix, null: false
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :api_keys, :token, unique: true

    create_table :provider_keys do |t|
      t.references :account, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :credential, null: false
      t.timestamps
    end
    add_index :provider_keys, [ :account_id, :provider ], unique: true
  end
end
