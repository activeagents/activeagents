class CreateTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :tickets do |t|
      t.string :subject, null: false
      t.text :body, null: false
      t.string :customer_email, null: false
      t.integer :status, null: false, default: 0

      # Filled in by TriageAgent
      t.string :category
      t.string :priority
      t.string :sentiment
      t.string :triage_summary
      t.datetime :triaged_at

      # Filled in by SummarizeAgent
      t.text :ai_summary

      t.timestamps
    end

    add_index :tickets, :status
    add_index :tickets, :priority
  end
end
