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

ActiveRecord::Schema[8.1].define(version: 2026_07_16_000006) do
  create_table "api_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_backend"
    t.string "name", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_api_users_on_token_digest", unique: true
  end

  create_table "blob_contents", force: :cascade do |t|
    t.string "blob_id", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.datetime "updated_at", null: false
    t.index ["blob_id"], name: "index_blob_contents_on_blob_id", unique: true
  end

  create_table "blobs", force: :cascade do |t|
    t.integer "api_user_id"
    t.string "backend", null: false
    t.string "blob_id", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.string "encryption", default: "plain", null: false
    t.bigint "size", null: false
    t.datetime "updated_at", null: false
    t.text "wrapped_dek"
    t.index ["api_user_id", "blob_id"], name: "index_blobs_on_api_user_id_and_blob_id", unique: true
    t.index ["api_user_id"], name: "index_blobs_on_api_user_id"
  end

  create_table "file_versions", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.integer "node_id", null: false
    t.datetime "updated_at", null: false
    t.index ["blob_id"], name: "index_file_versions_on_blob_id"
    t.index ["node_id"], name: "index_file_versions_on_node_id"
  end

  create_table "nodes", force: :cascade do |t|
    t.integer "api_user_id", null: false
    t.integer "blob_id"
    t.datetime "client_mtime"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.string "name", null: false
    t.string "original_name"
    t.bigint "original_parent_id"
    t.integer "parent_id"
    t.string "role"
    t.datetime "trashed_at"
    t.string "trashed_from"
    t.datetime "updated_at", null: false
    t.index ["api_user_id", "parent_id", "name"], name: "index_nodes_on_api_user_id_and_parent_id_and_name", unique: true
    t.index ["api_user_id"], name: "index_nodes_on_api_user_id"
    t.index ["blob_id"], name: "index_nodes_on_blob_id"
    t.index ["parent_id"], name: "index_nodes_on_parent_id"
  end

  create_table "shares", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "created_by_id", null: false
    t.datetime "expires_at"
    t.integer "grantee_id", null: false
    t.integer "node_id", null: false
    t.string "permission", default: "read", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_shares_on_created_by_id"
    t.index ["grantee_id"], name: "index_shares_on_grantee_id"
    t.index ["node_id", "grantee_id"], name: "index_shares_on_node_id_and_grantee_id", unique: true
    t.index ["node_id"], name: "index_shares_on_node_id"
  end

  create_table "uploads", force: :cascade do |t|
    t.integer "api_user_id", null: false
    t.string "backend"
    t.datetime "client_mtime"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.bigint "expected_size", null: false
    t.bigint "offset", default: 0, null: false
    t.string "path", null: false
    t.datetime "updated_at", null: false
    t.index ["api_user_id"], name: "index_uploads_on_api_user_id"
  end

  add_foreign_key "blobs", "api_users"
  add_foreign_key "file_versions", "blobs"
  add_foreign_key "file_versions", "nodes"
  add_foreign_key "nodes", "api_users"
  add_foreign_key "nodes", "blobs"
  add_foreign_key "nodes", "nodes", column: "parent_id"
  add_foreign_key "shares", "api_users", column: "created_by_id"
  add_foreign_key "shares", "api_users", column: "grantee_id"
  add_foreign_key "shares", "nodes"
  add_foreign_key "uploads", "api_users"
end
