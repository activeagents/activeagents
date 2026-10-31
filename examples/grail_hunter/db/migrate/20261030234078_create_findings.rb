class CreateFindings < ActiveRecord::Migration[8.1]
  def change
    create_table :findings do |t|
      t.references :hunt, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :discovery_run, foreign_key: true
      t.string :title, null: false
      t.string :url, null: false
      t.string :source
      t.integer :price_cents
      t.string :currency
      t.string :condition
      t.string :size
      t.string :image_url
      t.text :description
      t.integer :match_score
      t.string :verdict
      t.text :rationale
      t.json :red_flags
      t.string :scored_by, null: false, default: "agent"
      t.string :status, null: false, default: "new"
      t.datetime :listed_at

      t.timestamps
    end

    add_index :findings, [ :hunt_id, :url ], unique: true
    add_index :findings, [ :user_id, :status ]
  end
end
