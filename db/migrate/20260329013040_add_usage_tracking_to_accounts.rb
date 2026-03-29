class AddUsageTrackingToAccounts < ActiveRecord::Migration[8.2]
  def change
    add_column :accounts, :agent_runs_this_period, :integer, default: 0, null: false
    add_column :accounts, :agent_runs_limit, :integer, default: 3, null: false  # Low for testing
    add_column :accounts, :usage_period_start, :datetime
  end
end
