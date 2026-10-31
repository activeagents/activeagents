class CreateHunts < ActiveRecord::Migration[8.1]
  def change
    create_table :hunts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :brand
      t.string :category
      t.text :description
      t.string :keywords
      t.string :sizes
      t.integer :max_price_cents
      t.string :currency, null: false, default: "USD"
      t.string :condition, null: false, default: "any"
      t.string :frequency, null: false, default: "manual"
      t.string :status, null: false, default: "active"
      t.json :search_plan
      t.datetime :last_run_at
      t.datetime :next_run_at

      t.timestamps
    end

    add_index :hunts, [ :status, :next_run_at ]
  end
end
