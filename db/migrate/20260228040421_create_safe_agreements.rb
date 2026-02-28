class CreateSafeAgreements < ActiveRecord::Migration[8.2]
  def change
    create_table :safe_agreements do |t|
      t.references :account, null: false, foreign_key: true
      t.references :investor, null: false, foreign_key: true

      # SAFE terms (OCF compatible)
      t.decimal :investment_amount, precision: 15, scale: 2, null: false
      t.decimal :valuation_cap, precision: 15, scale: 2
      t.decimal :discount_percent, precision: 5, scale: 2
      t.string :safe_type, default: "post_money"
      t.boolean :pro_rata_rights, default: false

      # Status workflow
      t.string :status, default: "draft"
      t.datetime :sent_at
      t.datetime :signed_at
      t.datetime :converted_at
      t.datetime :cancelled_at

      # Conversion details (when SAFE converts)
      t.decimal :conversion_shares, precision: 15, scale: 0
      t.decimal :conversion_price_per_share, precision: 15, scale: 6
      t.string :conversion_round_name

      # Link to Stripe Atlas SAFE
      t.string :atlas_safe_id

      # External sync
      t.string :pulley_id
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :safe_agreements, :status
    add_index :safe_agreements, :pulley_id
    add_index :safe_agreements, :atlas_safe_id
  end
end
