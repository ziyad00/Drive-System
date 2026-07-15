class AddTrashToNodes < ActiveRecord::Migration[8.1]
  def change
    # role marks per-user sentinels ("root", "trash"). Trashed subtrees are
    # reparented under the trash sentinel; the root of a trashed subtree
    # remembers where it came from for restore.
    add_column :nodes, :role, :string
    add_column :nodes, :trashed_at, :datetime
    add_column :nodes, :trashed_from, :string
    add_column :nodes, :original_name, :string
    add_column :nodes, :original_parent_id, :bigint

    reversible do |direction|
      direction.up { execute "UPDATE nodes SET role = 'root' WHERE parent_id IS NULL" }
    end
  end
end
