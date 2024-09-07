class CreateUsersChats < ActiveRecord::Migration[7.1]
  def change
    create_table :users_chats do |t|
      t.references :user, null: false, foreign_key: true
      t.references :chat, null: false, foreign_key: true

      t.timestamps
    end
  end
end
