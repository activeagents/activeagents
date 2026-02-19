class CreateAccounts < ActiveRecord::Migration[8.2]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.references :owner, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
