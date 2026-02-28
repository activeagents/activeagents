class CreateInvestorDocuments < ActiveRecord::Migration[8.2]
  def change
    create_table :investor_documents do |t|
      t.references :account, null: false, foreign_key: true
      t.references :safe_agreement, foreign_key: true

      # Document info
      t.string :name, null: false
      t.string :document_type, null: false
      t.text :description
      t.string :version

      # Access control
      t.boolean :public_to_all_investors, default: false
      t.boolean :requires_accreditation, default: false

      t.timestamps
    end

    add_index :investor_documents, :document_type
  end
end
