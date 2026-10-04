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

ActiveRecord::Schema[8.1].define(version: 2026_10_04_004715) do
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
end
