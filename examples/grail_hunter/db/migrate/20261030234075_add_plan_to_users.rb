class AddPlanToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string
    add_column :users, :plan_key, :string, null: false, default: "pay_as_you_go"
    add_column :users, :subscribed_at, :datetime
    add_column :users, :subscription_renews_at, :datetime
    add_column :users, :admin, :boolean, null: false, default: false
  end
end
