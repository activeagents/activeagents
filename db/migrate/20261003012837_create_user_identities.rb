class CreateUserIdentities < ActiveRecord::Migration[8.2]
  def change
    create_table :user_identities do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :provider, null: false
      # The provider's immutable account id (GitHub's numeric user id), never
      # the login or email, which the person can change.
      t.string :uid, null: false
      t.string :login
      t.string :email
      t.timestamps
    end

    add_index :user_identities, [ :provider, :uid ], unique: true
    add_index :user_identities, [ :user_id, :provider ], unique: true
  end
end
