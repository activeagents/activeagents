class CreateInvestors < ActiveRecord::Migration[8.2]
  def change
    create_table :investors do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, foreign_key: true

      # Contact info
      t.string :email, null: false
      t.string :name, null: false
      t.string :legal_name
      t.string :phone

      # Investor type (OCF compatible)
      t.string :investor_type, default: "individual"
      t.string :entity_name
      t.string :entity_type

      # Address (for legal docs)
      t.string :address_line1
      t.string :address_line2
      t.string :city
      t.string :state
      t.string :postal_code
      t.string :country, default: "US"

      # Portal access
      t.string :access_token
      t.datetime :access_token_expires_at
      t.datetime :last_accessed_at
      t.boolean :portal_enabled, default: true

      # External sync
      t.string :pulley_id
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :investors, [ :account_id, :email ], unique: true
    add_index :investors, :access_token, unique: true
    add_index :investors, :pulley_id
  end
end
