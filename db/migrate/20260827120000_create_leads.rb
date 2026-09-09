class CreateLeads < ActiveRecord::Migration[8.2]
  def change
    create_table :leads do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :company
      t.string :service_type, null: false
      t.text :message
      t.string :source
      t.boolean :synced_to_resend, default: false, null: false
      t.datetime :notified_at

      t.timestamps
    end

    add_index :leads, :email
    add_index :leads, :service_type
    add_index :leads, :created_at
  end
end
