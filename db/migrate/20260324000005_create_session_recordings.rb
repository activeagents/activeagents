# frozen_string_literal: true

class CreateSessionRecordings < ActiveRecord::Migration[8.0]
  def change
    create_table :session_recordings do |t|
      t.references :agent_run, null: true, foreign_key: true
      t.references :sandbox_session, null: true, foreign_key: true
      t.string :name # e.g., "checkout_flow"
      t.integer :status, default: 0, null: false # recording, completed, failed
      t.integer :duration_ms
      t.integer :action_count, default: 0
      t.json :metadata, default: {}
      t.timestamps
    end

    create_table :recording_actions do |t|
      t.references :session_recording, null: false, foreign_key: true
      t.string :action_type, null: false # navigate, click, type, snapshot, scroll
      t.integer :sequence, null: false
      t.integer :timestamp_ms, null: false
      t.string :selector # CSS selector or element ref
      t.text :value # typed text, url, etc.
      t.string :screenshot_key # S3/GCS key
      t.string :dom_snapshot_key
      t.json :metadata, default: {}
      t.timestamps
    end

    add_index :recording_actions, [:session_recording_id, :sequence], unique: true

    create_table :recording_snapshots do |t|
      t.references :session_recording, null: false, foreign_key: true
      t.references :recording_action, null: true, foreign_key: true
      t.string :storage_key, null: false
      t.string :snapshot_type, null: false # screenshot, dom, full_page
      t.integer :width
      t.integer :height
      t.integer :file_size_bytes
      t.timestamps
    end

    add_index :recording_snapshots, :storage_key, unique: true
  end
end
