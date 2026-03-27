class AddSignupSourceToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :signup_source, :string
  end
end
