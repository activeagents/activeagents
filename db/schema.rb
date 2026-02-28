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

ActiveRecord::Schema[8.2].define(version: 2026_02_28_040425) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_memberships", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id", "user_id"], name: "index_account_memberships_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_account_memberships_on_account_id"
    t.index ["user_id"], name: "index_account_memberships_on_user_id"
  end

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_accounts_on_owner_id"
  end

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

  create_table "cap_table_entries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.decimal "exercise_price", precision: 15, scale: 6
    t.datetime "expiration_date"
    t.datetime "grant_date"
    t.bigint "investor_id"
    t.jsonb "metadata", default: {}
    t.decimal "ownership_percent", precision: 10, scale: 6
    t.string "pulley_id"
    t.bigint "safe_agreement_id"
    t.string "security_class"
    t.string "security_type", null: false
    t.decimal "shares", precision: 15
    t.string "stakeholder_name", null: false
    t.string "stakeholder_type", null: false
    t.datetime "updated_at", null: false
    t.decimal "vested_shares", precision: 15
    t.index ["account_id"], name: "index_cap_table_entries_on_account_id"
    t.index ["investor_id"], name: "index_cap_table_entries_on_investor_id"
    t.index ["pulley_id"], name: "index_cap_table_entries_on_pulley_id"
    t.index ["safe_agreement_id"], name: "index_cap_table_entries_on_safe_agreement_id"
    t.index ["security_type"], name: "index_cap_table_entries_on_security_type"
    t.index ["stakeholder_type"], name: "index_cap_table_entries_on_stakeholder_type"
  end

  create_table "document_access_grants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "granted_at", null: false
    t.bigint "investor_document_id", null: false
    t.bigint "investor_id", null: false
    t.datetime "revoked_at"
    t.datetime "updated_at", null: false
    t.index ["investor_document_id", "investor_id"], name: "idx_doc_grants_unique", unique: true
    t.index ["investor_document_id"], name: "index_document_access_grants_on_investor_document_id"
    t.index ["investor_id"], name: "index_document_access_grants_on_investor_id"
  end

  create_table "document_access_logs", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.bigint "investor_document_id", null: false
    t.bigint "investor_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.index ["created_at"], name: "index_document_access_logs_on_created_at"
    t.index ["investor_document_id", "created_at"], name: "idx_on_investor_document_id_created_at_a40801d0d5"
    t.index ["investor_document_id"], name: "index_document_access_logs_on_investor_document_id"
    t.index ["investor_id"], name: "index_document_access_logs_on_investor_id"
  end

  create_table "investor_documents", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "document_type", null: false
    t.string "name", null: false
    t.boolean "public_to_all_investors", default: false
    t.boolean "requires_accreditation", default: false
    t.bigint "safe_agreement_id"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["account_id"], name: "index_investor_documents_on_account_id"
    t.index ["document_type"], name: "index_investor_documents_on_document_type"
    t.index ["safe_agreement_id"], name: "index_investor_documents_on_safe_agreement_id"
  end

  create_table "investors", force: :cascade do |t|
    t.string "access_token"
    t.datetime "access_token_expires_at"
    t.bigint "account_id", null: false
    t.string "address_line1"
    t.string "address_line2"
    t.string "city"
    t.string "country", default: "US"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "entity_name"
    t.string "entity_type"
    t.string "investor_type", default: "individual"
    t.datetime "last_accessed_at"
    t.string "legal_name"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.string "phone"
    t.boolean "portal_enabled", default: true
    t.string "postal_code"
    t.string "pulley_id"
    t.string "state"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["access_token"], name: "index_investors_on_access_token", unique: true
    t.index ["account_id", "email"], name: "index_investors_on_account_id_and_email", unique: true
    t.index ["account_id"], name: "index_investors_on_account_id"
    t.index ["pulley_id"], name: "index_investors_on_pulley_id"
    t.index ["user_id"], name: "index_investors_on_user_id"
  end

  create_table "pay_charges", force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "amount_refunded"
    t.integer "application_fee_amount"
    t.datetime "created_at", null: false
    t.string "currency"
    t.bigint "customer_id", null: false
    t.jsonb "data"
    t.jsonb "metadata"
    t.string "processor_id", null: false
    t.string "stripe_account"
    t.bigint "subscription_id"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_charges_on_customer_id_and_processor_id", unique: true
    t.index ["subscription_id"], name: "index_pay_charges_on_subscription_id"
  end

  create_table "pay_customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data"
    t.boolean "default"
    t.datetime "deleted_at", precision: nil
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "processor", null: false
    t.string "processor_id"
    t.string "stripe_account"
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "deleted_at"], name: "pay_customer_owner_index", unique: true
    t.index ["processor", "processor_id"], name: "index_pay_customers_on_processor_and_processor_id", unique: true
  end

  create_table "pay_merchants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data"
    t.boolean "default"
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "processor", null: false
    t.string "processor_id"
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "processor"], name: "index_pay_merchants_on_owner_type_and_owner_id_and_processor"
  end

  create_table "pay_payment_methods", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.jsonb "data"
    t.boolean "default"
    t.string "processor_id", null: false
    t.string "stripe_account"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_payment_methods_on_customer_id_and_processor_id", unique: true
  end

  create_table "pay_subscriptions", force: :cascade do |t|
    t.decimal "application_fee_percent", precision: 8, scale: 2
    t.datetime "created_at", null: false
    t.datetime "current_period_end", precision: nil
    t.datetime "current_period_start", precision: nil
    t.bigint "customer_id", null: false
    t.jsonb "data"
    t.datetime "ends_at", precision: nil
    t.jsonb "metadata"
    t.boolean "metered"
    t.string "name", null: false
    t.string "pause_behavior"
    t.datetime "pause_resumes_at", precision: nil
    t.datetime "pause_starts_at", precision: nil
    t.string "payment_method_id"
    t.string "processor_id", null: false
    t.string "processor_plan", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", null: false
    t.string "stripe_account"
    t.datetime "trial_ends_at", precision: nil
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_subscriptions_on_customer_id_and_processor_id", unique: true
    t.index ["metered"], name: "index_pay_subscriptions_on_metered"
    t.index ["pause_starts_at"], name: "index_pay_subscriptions_on_pause_starts_at"
  end

  create_table "pay_webhooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "event"
    t.string "event_type"
    t.string "processor"
    t.datetime "updated_at", null: false
  end

  create_table "plans", force: :cascade do |t|
    t.boolean "active", default: true
    t.integer "annual_price_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.jsonb "features", default: {}
    t.integer "included_seats", default: 1
    t.integer "included_workspaces", default: 0
    t.string "name", null: false
    t.integer "price_cents", default: 0, null: false
    t.string "slug", null: false
    t.string "stripe_annual_price_id"
    t.string "stripe_monthly_price_id"
    t.integer "trial_days", default: 0
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_plans_on_active"
    t.index ["slug"], name: "index_plans_on_slug", unique: true
  end

  create_table "safe_agreements", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "atlas_safe_id"
    t.datetime "cancelled_at"
    t.decimal "conversion_price_per_share", precision: 15, scale: 6
    t.string "conversion_round_name"
    t.decimal "conversion_shares", precision: 15
    t.datetime "converted_at"
    t.datetime "created_at", null: false
    t.decimal "discount_percent", precision: 5, scale: 2
    t.decimal "investment_amount", precision: 15, scale: 2, null: false
    t.bigint "investor_id", null: false
    t.jsonb "metadata", default: {}
    t.boolean "pro_rata_rights", default: false
    t.string "pulley_id"
    t.string "safe_type", default: "post_money"
    t.datetime "sent_at"
    t.datetime "signed_at"
    t.string "status", default: "draft"
    t.datetime "updated_at", null: false
    t.decimal "valuation_cap", precision: 15, scale: 2
    t.index ["account_id"], name: "index_safe_agreements_on_account_id"
    t.index ["atlas_safe_id"], name: "index_safe_agreements_on_atlas_safe_id"
    t.index ["investor_id"], name: "index_safe_agreements_on_investor_id"
    t.index ["pulley_id"], name: "index_safe_agreements_on_pulley_id"
    t.index ["status"], name: "index_safe_agreements_on_status"
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

  add_foreign_key "account_memberships", "accounts"
  add_foreign_key "account_memberships", "users"
  add_foreign_key "accounts", "users", column: "owner_id"
  add_foreign_key "agent_runs", "agents"
  add_foreign_key "agent_versions", "agents"
  add_foreign_key "agents", "users"
  add_foreign_key "cap_table_entries", "accounts"
  add_foreign_key "cap_table_entries", "investors"
  add_foreign_key "cap_table_entries", "safe_agreements"
  add_foreign_key "document_access_grants", "investor_documents"
  add_foreign_key "document_access_grants", "investors"
  add_foreign_key "document_access_logs", "investor_documents"
  add_foreign_key "document_access_logs", "investors"
  add_foreign_key "investor_documents", "accounts"
  add_foreign_key "investor_documents", "safe_agreements"
  add_foreign_key "investors", "accounts"
  add_foreign_key "investors", "users"
  add_foreign_key "pay_charges", "pay_customers", column: "customer_id"
  add_foreign_key "pay_charges", "pay_subscriptions", column: "subscription_id"
  add_foreign_key "pay_payment_methods", "pay_customers", column: "customer_id"
  add_foreign_key "pay_subscriptions", "pay_customers", column: "customer_id"
  add_foreign_key "safe_agreements", "accounts"
  add_foreign_key "safe_agreements", "investors"
  add_foreign_key "sessions", "users"
end
