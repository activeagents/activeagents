class CreateCharges < ActiveRecord::Migration[8.1]
  def change
    create_table :charges do |t|
      t.references :user, null: false, foreign_key: true
      t.references :discovery_run, foreign_key: true
      t.string :kind, null: false
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "USD"
      t.string :description, null: false
      t.string :status, null: false, default: "settled"
      t.date :period_start
      t.date :period_end

      t.timestamps
    end

    add_index :charges, [ :user_id, :created_at ]
  end
end
