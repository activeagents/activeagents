class AddSyncedToLoopsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :synced_to_resend, :boolean, default: false, null: false
  end
end
