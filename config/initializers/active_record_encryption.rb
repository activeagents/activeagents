# frozen_string_literal: true

# Active Record Encryption key material (used by `encrypts` attributes:
# ApiKey#token, ProviderKey#api_key).
#
# Keys are taken from the environment when provided, which is the intended
# production setup (generate values with `bin/rails db:encryption:init`).
# When absent they are derived from `secret_key_base` so every environment —
# development, test, staging — can encrypt out of the box without new
# secrets. The derivation is stable as long as `secret_key_base` is stable;
# rotating `secret_key_base` without setting explicit keys first would make
# previously encrypted values unreadable.
Rails.application.config.active_record.encryption.tap do |encryption|
  derive = lambda do |purpose|
    Rails.application.key_generator.generate_key("active_record_encryption.#{purpose}", 32).unpack1("H*")
  end

  encryption.primary_key         = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence || derive.call("primary_key")
  encryption.deterministic_key   = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence || derive.call("deterministic_key")
  encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence || derive.call("key_derivation_salt")
end
