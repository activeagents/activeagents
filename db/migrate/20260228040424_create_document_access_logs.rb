class CreateDocumentAccessLogs < ActiveRecord::Migration[8.2]
  def change
    create_table :document_access_logs do |t|
      t.references :investor_document, null: false, foreign_key: true
      t.references :investor, null: false, foreign_key: true

      t.string :action, null: false
      t.string :ip_address
      t.string :user_agent
      t.integer :duration_seconds

      t.datetime :created_at, null: false
    end

    add_index :document_access_logs, :created_at
    add_index :document_access_logs, [ :investor_document_id, :created_at ]
  end
end
