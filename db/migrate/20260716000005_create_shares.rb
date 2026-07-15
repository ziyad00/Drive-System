class CreateShares < ActiveRecord::Migration[8.1]
  def change
    create_table :shares do |t|
      t.references :node, null: false, foreign_key: true
      t.references :grantee, null: false, foreign_key: { to_table: :api_users }
      t.references :created_by, null: false, foreign_key: { to_table: :api_users }
      t.string :permission, null: false, default: "read"
      t.datetime :expires_at

      t.timestamps
    end

    add_index :shares, [ :node_id, :grantee_id ], unique: true
  end
end
