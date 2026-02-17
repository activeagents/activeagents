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

ActiveRecord::Schema[8.2].define(version: 2026_02_17_003024) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_runs", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "error_backtrace"
    t.text "error_message"
    t.jsonb "input_params", default: {}
    t.text "input_prompt"
    t.integer "input_tokens"
    t.jsonb "logs", default: []
    t.text "output"
    t.jsonb "output_metadata", default: {}
    t.integer "output_tokens"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.integer "total_tokens"
    t.string "trace_id"
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_agent_runs_on_agent_id"
    t.index ["created_at"], name: "index_agent_runs_on_created_at"
    t.index ["status"], name: "index_agent_runs_on_status"
    t.index ["trace_id"], name: "index_agent_runs_on_trace_id"
  end

  create_table "agent_templates", force: :cascade do |t|
    t.jsonb "appearance", default: {}
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "featured", default: false
    t.string "icon"
    t.jsonb "instruction_sets", default: []
    t.text "instructions"
    t.string "model", default: "gpt-4o-mini"
    t.jsonb "model_config", default: {}
    t.string "name", null: false
    t.string "preset_type"
    t.string "provider", default: "openai"
    t.boolean "public", default: true
    t.string "slug", null: false
    t.jsonb "tools", default: []
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0
    t.index ["category"], name: "index_agent_templates_on_category"
    t.index ["featured"], name: "index_agent_templates_on_featured"
    t.index ["slug"], name: "index_agent_templates_on_slug", unique: true
    t.index ["usage_count"], name: "index_agent_templates_on_usage_count"
  end

  create_table "agent_versions", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.string "change_summary"
    t.jsonb "configuration_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "created_by"
    t.datetime "updated_at", null: false
    t.integer "version_number", default: 1, null: false
    t.index ["agent_id", "version_number"], name: "index_agent_versions_on_agent_id_and_version_number", unique: true
    t.index ["agent_id"], name: "index_agent_versions_on_agent_id"
  end

  create_table "agents", force: :cascade do |t|
    t.string "agent_class_name"
    t.jsonb "appearance", default: {}
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "instruction_sets", default: []
    t.text "instructions"
    t.jsonb "mcp_servers", default: []
    t.string "model", default: "gpt-4o-mini"
    t.jsonb "model_config", default: {}
    t.string "name", null: false
    t.string "preset_type"
    t.string "provider", default: "openai"
    t.jsonb "response_format", default: {}
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "tools", default: []
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["provider"], name: "index_agents_on_provider"
    t.index ["slug"], name: "index_agents_on_slug", unique: true
    t.index ["status"], name: "index_agents_on_status"
    t.index ["user_id", "slug"], name: "index_agents_on_user_id_and_slug", unique: true
    t.index ["user_id"], name: "index_agents_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "agent_runs", "agents"
  add_foreign_key "agent_versions", "agents"
  add_foreign_key "agents", "users"
  add_foreign_key "sessions", "users"
end
