# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_11_000001) do
  create_table "playground_messages", force: :cascade do |t|
    t.string "agent_name"
    t.text "content"
    t.datetime "created_at", null: false
    t.json "metadata", default: {}
    t.integer "playground_session_id", null: false
    t.integer "position", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["playground_session_id", "position"], name: "idx_on_playground_session_id_position_f0cc96f82a"
    t.index ["playground_session_id"], name: "index_playground_messages_on_playground_session_id"
  end

  create_table "playground_sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "metadata", default: {}
    t.string "session_token", null: false
    t.json "shared_context", default: {}
    t.string "status", default: "active"
    t.datetime "updated_at", null: false
    t.index ["session_token"], name: "index_playground_sessions_on_session_token", unique: true
  end

  add_foreign_key "playground_messages", "playground_sessions"
end
