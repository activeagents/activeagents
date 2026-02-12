class CreatePlaygroundTables < ActiveRecord::Migration[8.1]
  def change
    create_table :playground_sessions do |t|
      t.string :session_token, null: false
      t.string :status, default: "active"
      t.json :shared_context, default: {}
      t.json :metadata, default: {}
      t.timestamps
    end

    add_index :playground_sessions, :session_token, unique: true

    create_table :playground_messages do |t|
      t.references :playground_session, null: false, foreign_key: true
      t.string :role, null: false
      t.string :agent_name
      t.text :content
      t.integer :position, null: false
      t.json :metadata, default: {}
      t.timestamps
    end

    add_index :playground_messages, [:playground_session_id, :position]
  end
end
