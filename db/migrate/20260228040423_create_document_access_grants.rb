class CreateDocumentAccessGrants < ActiveRecord::Migration[8.2]
  def change
    create_table :document_access_grants do |t|
      t.references :investor_document, null: false, foreign_key: true
      t.references :investor, null: false, foreign_key: true

      t.datetime :granted_at, null: false
      t.datetime :expires_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :document_access_grants, [ :investor_document_id, :investor_id ],
              unique: true, name: "idx_doc_grants_unique"
  end
end
