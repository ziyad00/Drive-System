class CreateNodes < ActiveRecord::Migration[8.1]
  def change
    create_table :nodes do |t|
      t.references :api_user, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :nodes }
      t.references :blob, foreign_key: true
      t.string :kind, null: false
      t.string :name, null: false
      t.string :content_type
      t.datetime :client_mtime

      t.timestamps
    end

    # Sibling names are unique within a folder. Every real node hangs off
    # the per-user root sentinel, so parent_id is never NULL for them and
    # the constraint has no NULL loophole.
    add_index :nodes, [ :api_user_id, :parent_id, :name ], unique: true
  end
end
