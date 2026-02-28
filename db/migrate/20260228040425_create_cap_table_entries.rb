class CreateCapTableEntries < ActiveRecord::Migration[8.2]
  def change
    create_table :cap_table_entries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :investor, foreign_key: true
      t.references :safe_agreement, foreign_key: true

      # Stakeholder info
      t.string :stakeholder_name, null: false
      t.string :stakeholder_type, null: false

      # Security details (OCF compatible)
      t.string :security_type, null: false
      t.string :security_class
      t.decimal :shares, precision: 15, scale: 0
      t.decimal :ownership_percent, precision: 10, scale: 6

      # For options/warrants
      t.decimal :exercise_price, precision: 15, scale: 6
      t.datetime :grant_date
      t.datetime :expiration_date
      t.decimal :vested_shares, precision: 15, scale: 0

      # External sync
      t.string :pulley_id
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :cap_table_entries, :stakeholder_type
    add_index :cap_table_entries, :security_type
    add_index :cap_table_entries, :pulley_id
  end
end
