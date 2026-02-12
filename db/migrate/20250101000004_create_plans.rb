class CreatePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :plans do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :price_cents, null: false, default: 0
      t.integer :annual_price_cents, null: false, default: 0
      t.string :stripe_monthly_price_id
      t.string :stripe_annual_price_id
      t.integer :trial_days, null: false, default: 0
      t.integer :included_seats, null: false, default: 1
      t.integer :included_workspaces, null: false, default: 0
      t.jsonb :features, null: false, default: {}
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :plans, :slug, unique: true
    add_index :plans, :active
  end
end
