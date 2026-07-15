class CreateEncryptionGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :encryption_groups do |t|
      t.references :owner, null: false, foreign_key: { to_table: :api_users }
      t.string :name, null: false
      t.integer :capacity, null: false, default: 8
      t.integer :epoch, null: false, default: 0
      t.text :public_state   # public ratchet-tree keys only — never secrets
      t.timestamps
    end

    create_table :group_members do |t|
      t.references :encryption_group, null: false, foreign_key: true
      t.references :api_user, null: false, foreign_key: true
      t.integer :leaf_id, null: false
      t.timestamps
    end
    add_index :group_members, [ :encryption_group_id, :api_user_id ], unique: true
    add_index :group_members, [ :encryption_group_id, :leaf_id ], unique: true

    # Append-only commit log. Each message carries public path keys and
    # per-member ENCRYPTED path secrets — opaque to the server.
    create_table :group_commits do |t|
      t.references :encryption_group, null: false, foreign_key: true
      t.references :committer, null: false, foreign_key: { to_table: :api_users }
      t.integer :epoch, null: false
      t.text :message, null: false
      t.datetime :created_at, null: false
    end
    add_index :group_commits, [ :encryption_group_id, :epoch ], unique: true
  end
end
