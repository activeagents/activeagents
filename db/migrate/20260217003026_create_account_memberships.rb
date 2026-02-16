class CreateAccountMemberships < ActiveRecord::Migration[8.2]
  def change
    create_table :account_memberships do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"

      t.timestamps
    end

    add_index :account_memberships, [ :account_id, :user_id ], unique: true
  end
end
