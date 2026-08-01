# frozen_string_literal: true

# ActiveRecord resources reported by a connected app (POST /v1/resources,
# same Bearer plane as telemetry). Each row is one model class of one
# service — the manifest the platform scaffolds admin agents from, the way
# rails_admin scaffolds an admin UI. agent_id links the resource to the
# admin agent generated for it, when one has been.
class CreateAdminResources < ActiveRecord::Migration[8.2]
  def change
    create_table :admin_resources do |t|
      t.references :account, null: false, foreign_key: true
      t.references :agent, foreign_key: true
      t.string :service_name, null: false
      t.string :environment
      t.string :name, null: false
      t.string :table_name
      t.jsonb :columns, default: [], null: false
      t.jsonb :associations, default: [], null: false
      t.integer :record_count
      t.string :admin_route
      t.jsonb :metadata, default: {}, null: false
      t.datetime :first_reported_at
      t.datetime :last_reported_at
      t.timestamps
    end
    add_index :admin_resources, [ :account_id, :service_name, :name ], unique: true
    add_index :admin_resources, [ :account_id, :service_name ]
  end
end
