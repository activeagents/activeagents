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

ActiveRecord::Schema[8.1].define(version: 2026_07_15_173001) do
  create_table "active_agent_telemetry_traces", force: :cascade do |t|
    t.string "agent_action"
    t.string "agent_class"
    t.datetime "created_at", null: false
    t.string "environment"
    t.text "error_message"
    t.json "resource_attributes", default: {}
    t.json "sdk_info", default: {}
    t.string "service_name"
    t.json "spans", default: []
    t.string "status", default: "UNSET"
    t.datetime "timestamp", null: false
    t.integer "total_duration_ms"
    t.integer "total_input_tokens", default: 0
    t.integer "total_output_tokens", default: 0
    t.integer "total_thinking_tokens", default: 0
    t.string "trace_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_class"], name: "index_active_agent_telemetry_traces_on_agent_class"
    t.index ["environment"], name: "index_active_agent_telemetry_traces_on_environment"
    t.index ["service_name"], name: "index_active_agent_telemetry_traces_on_service_name"
    t.index ["status"], name: "index_active_agent_telemetry_traces_on_status"
    t.index ["timestamp"], name: "index_active_agent_telemetry_traces_on_timestamp"
    t.index ["trace_id"], name: "index_active_agent_telemetry_traces_on_trace_id", unique: true
  end

  create_table "agent_contexts", force: :cascade do |t|
    t.string "action_name", null: false
    t.string "agent_name", null: false
    t.integer "contextable_id"
    t.string "contextable_type"
    t.datetime "created_at", null: false
    t.text "instructions"
    t.json "options", default: {}
    t.integer "total_input_tokens", default: 0
    t.integer "total_output_tokens", default: 0
    t.string "trace_id"
    t.datetime "updated_at", null: false
    t.index ["agent_name", "action_name"], name: "index_agent_contexts_on_agent_name_and_action_name"
    t.index ["contextable_type", "contextable_id"], name: "index_agent_contexts_on_contextable"
    t.index ["created_at"], name: "index_agent_contexts_on_created_at"
    t.index ["trace_id"], name: "index_agent_contexts_on_trace_id"
  end

  create_table "agent_generations", force: :cascade do |t|
    t.integer "agent_context_id", null: false
    t.integer "cached_tokens", default: 0
    t.text "content"
    t.datetime "created_at", null: false
    t.float "duration_seconds"
    t.string "finish_reason"
    t.integer "input_tokens", default: 0
    t.string "model"
    t.integer "output_tokens", default: 0
    t.json "provenance", default: {}
    t.string "provider"
    t.json "raw_response"
    t.integer "reasoning_tokens", default: 0
    t.json "tool_calls", default: []
    t.string "trace_id"
    t.datetime "updated_at", null: false
    t.index ["agent_context_id", "created_at"], name: "index_agent_generations_on_agent_context_id_and_created_at"
    t.index ["agent_context_id"], name: "index_agent_generations_on_agent_context_id"
    t.index ["finish_reason"], name: "index_agent_generations_on_finish_reason"
    t.index ["model"], name: "index_agent_generations_on_model"
    t.index ["trace_id"], name: "index_agent_generations_on_trace_id"
  end

  create_table "agent_messages", force: :cascade do |t|
    t.integer "agent_context_id", null: false
    t.json "attachments", default: []
    t.text "content"
    t.string "content_checksum"
    t.datetime "created_at", null: false
    t.json "metadata", default: {}
    t.json "provenance", default: {}
    t.string "role", null: false
    t.json "tool_arguments", default: {}
    t.string "tool_call_id"
    t.string "tool_name"
    t.json "tool_result"
    t.datetime "updated_at", null: false
    t.index ["agent_context_id", "created_at"], name: "index_agent_messages_on_agent_context_id_and_created_at"
    t.index ["agent_context_id"], name: "index_agent_messages_on_agent_context_id"
    t.index ["role"], name: "index_agent_messages_on_role"
    t.index ["tool_call_id"], name: "index_agent_messages_on_tool_call_id"
  end

  create_table "replies", force: :cascade do |t|
    t.boolean "ai_generated", default: false, null: false
    t.string "author", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.boolean "draft", default: false, null: false
    t.integer "ticket_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ticket_id"], name: "index_replies_on_ticket_id"
  end

  create_table "tickets", force: :cascade do |t|
    t.text "ai_summary"
    t.text "body", null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.string "customer_email", null: false
    t.string "priority"
    t.string "sentiment"
    t.integer "status", default: 0, null: false
    t.string "subject", null: false
    t.string "triage_summary"
    t.datetime "triaged_at"
    t.datetime "updated_at", null: false
    t.index ["priority"], name: "index_tickets_on_priority"
    t.index ["status"], name: "index_tickets_on_status"
  end

  add_foreign_key "agent_generations", "agent_contexts"
  add_foreign_key "agent_messages", "agent_contexts"
  add_foreign_key "replies", "tickets"
end
