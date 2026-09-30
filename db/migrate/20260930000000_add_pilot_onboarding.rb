class AddPilotOnboarding < ActiveRecord::Migration[8.1]
  def change
    add_reference :sessions, :account, foreign_key: { on_delete: :nullify }
    add_column :accounts, :checkout_url, :text
    add_column :accounts, :checkout_expires_at, :datetime

    create_table :pro_access_grants do |t|
      t.references :account, null: false, index: { unique: true }, foreign_key: true
      t.references :granted_by, null: false, foreign_key: { to_table: :users }
      t.string :source, null: false
      t.text :reason, null: false
      t.datetime :starts_at, null: false
      t.date :review_on, null: false
      t.datetime :expires_at
      t.datetime :revoked_at
      t.datetime :expiration_recorded_at
      t.timestamps
    end

    create_table :pro_access_events do |t|
      t.references :pro_access_grant, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.jsonb :details, null: false, default: {}
      t.datetime :notified_at
      t.timestamps
    end

    create_table :workspace_invitations do |t|
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.references :accepted_by, foreign_key: { to_table: :users }
      t.references :account, foreign_key: true
      t.string :email_address, null: false
      t.string :workspace_name, null: false
      t.string :source, null: false, default: "retainer_pilot"
      t.text :reason, null: false
      t.date :review_on, null: false
      t.datetime :grant_expires_at
      t.string :token_digest
      t.datetime :token_expires_at
      t.integer :delivery_version, null: false, default: 0
      t.string :delivery_state, null: false, default: "draft"
      t.string :delivery_error
      t.datetime :sent_at
      t.datetime :accepted_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :workspace_invitations, :token_digest, unique: true
    add_index :workspace_invitations, :email_address, unique: true,
      where: "accepted_at IS NULL AND revoked_at IS NULL", name: "index_pending_invitation_email"

    create_table :newsletter_subscriptions do |t|
      t.string :email_address, null: false
      t.datetime :consented_at, null: false
      t.datetime :confirmed_at
      t.datetime :synced_at
      t.timestamps
    end
    add_index :newsletter_subscriptions, :email_address, unique: true
  end
end
