class CreateBlobs < ActiveRecord::Migration[8.1]
  def change
    create_table :blobs do |t|
      t.string :blob_id, null: false
      t.bigint :size, null: false
      t.string :backend, null: false

      t.timestamps
    end

    add_index :blobs, :blob_id, unique: true
  end
end
