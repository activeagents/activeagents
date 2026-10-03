class AddPasswordSetToUsers < ActiveRecord::Migration[8.2]
  def change
    # False while the password digest is a random value the person never saw,
    # as for an account created by signing in with GitHub.
    add_column :users, :password_set, :boolean, default: true, null: false
  end
end
