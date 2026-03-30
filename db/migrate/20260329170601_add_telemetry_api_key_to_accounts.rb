class AddTelemetryApiKeyToAccounts < ActiveRecord::Migration[8.2]
  def change
    add_column :accounts, :telemetry_api_key, :string
    add_index :accounts, :telemetry_api_key, unique: true
  end
end
