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

ActiveRecord::Schema[8.1].define(version: 2026_10_04_013645) do
  create_table "oidc_providers", force: :cascade do |t|
    t.string "issuer", null: false
    t.string "client_id", null: false
    t.string "client_secret", null: false
    t.string "name", default: "OIDC", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "oidc_sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "oidc_sid", null: false
    t.string "session_id", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_oidc_sessions_on_expires_at"
    t.index ["oidc_sid"], name: "index_oidc_sessions_on_oidc_sid", unique: true
    t.index ["user_id"], name: "index_oidc_sessions_on_user_id"
  end

  create_table "uptime_checks", force: :cascade do |t|
    t.integer "monitor_id", null: false
    t.string "status", null: false
    t.integer "latency_ms"
    t.string "message"
    t.datetime "checked_at", null: false
    t.index ["checked_at"], name: "index_uptime_checks_on_checked_at"
    t.index ["monitor_id", "checked_at"], name: "index_uptime_checks_on_monitor_id_and_checked_at"
  end

  create_table "uptime_monitors", force: :cascade do |t|
    t.integer "source_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.string "target", null: false
    t.integer "interval", null: false
    t.integer "timeout", null: false
    t.integer "retries", null: false
    t.json "options", default: {}, null: false
    t.string "defined_in", null: false
    t.datetime "retired_at"
    t.string "state", default: "pending", null: false
    t.datetime "state_changed_at"
    t.integer "consecutive_failures", default: 0, null: false
    t.datetime "last_checked_at"
    t.datetime "next_check_at"
    t.integer "last_latency_ms"
    t.string "last_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["next_check_at"], name: "index_uptime_monitors_on_next_check_at"
    t.index ["source_id", "key"], name: "index_uptime_monitors_on_source_id_and_key", unique: true
    t.index ["source_id"], name: "index_uptime_monitors_on_source_id"
  end

  create_table "uptime_sources", force: :cascade do |t|
    t.string "name", null: false
    t.string "path", null: false
    t.datetime "synced_at"
    t.text "sync_errors"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "uptime_state_changes", force: :cascade do |t|
    t.integer "monitor_id", null: false
    t.string "from_state", null: false
    t.string "to_state", null: false
    t.string "message"
    t.datetime "changed_at", null: false
    t.index ["monitor_id", "changed_at"], name: "index_uptime_state_changes_on_monitor_id_and_changed_at"
  end

  create_table "users", force: :cascade do |t|
    t.string "oidc_issuer"
    t.string "oidc_sub"
    t.string "email"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "password_digest"
    t.string "session_token"
    t.index ["oidc_issuer", "oidc_sub"], name: "index_users_on_oidc_issuer_and_oidc_sub", unique: true
  end

  add_foreign_key "oidc_sessions", "users"
  add_foreign_key "uptime_checks", "uptime_monitors", column: "monitor_id"
  add_foreign_key "uptime_monitors", "uptime_sources", column: "source_id"
  add_foreign_key "uptime_state_changes", "uptime_monitors", column: "monitor_id"
end
