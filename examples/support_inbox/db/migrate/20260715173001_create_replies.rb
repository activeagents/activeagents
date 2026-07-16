class CreateReplies < ActiveRecord::Migration[8.1]
  def change
    create_table :replies do |t|
      t.references :ticket, null: false, foreign_key: true
      t.string :author, null: false
      t.text :body, null: false
      t.boolean :ai_generated, null: false, default: false
      t.boolean :draft, null: false, default: false

      t.timestamps
    end
  end
end
