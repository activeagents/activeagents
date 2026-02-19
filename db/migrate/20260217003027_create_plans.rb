class CreatePlans < ActiveRecord::Migration[8.2]
  def change
    create_table :plans do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :price_cents, null: false, default: 0
      t.integer :annual_price_cents, null: false, default: 0
      t.string :stripe_monthly_price_id
      t.string :stripe_annual_price_id
      t.integer :trial_days, default: 0
      t.integer :included_seats, default: 1
      t.integer :included_workspaces, default: 0
      t.jsonb :features, default: {}
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :plans, :slug, unique: true
    add_index :plans, :active
  end
end
