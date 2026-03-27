class AddEmailVerificationToUsers < ActiveRecord::Migration[8.2]
  def change
    add_column :users, :email_verified, :boolean, default: false, null: false
    add_column :users, :email_verification_token, :string
    add_column :users, :email_verification_sent_at, :datetime
    add_column :users, :profile_completed, :boolean, default: false, null: false
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string
    add_column :users, :company_name, :string
    add_column :users, :job_title, :string

    add_index :users, :email_verification_token, unique: true
  end
end
